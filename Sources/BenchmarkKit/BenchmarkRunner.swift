import CurrentDomain
import DiffKit
import Foundation
import GitParsers
import GraphKit

public struct BenchmarkRunner: Sendable {
  public init() {}

  public func run(
    repositoryURL: URL,
    iterations: Int,
    gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git")
  ) throws -> BenchmarkReport {
    guard iterations >= 3 else {
      throw BenchmarkError.invalidArguments("At least three iterations are required.")
    }
    let manifestURL = repositoryURL.appendingPathComponent(".git/current-benchmark.json")
    let manifest = try JSONDecoder().decode(
      FixtureManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let gitVersion = try command(gitExecutable, ["--version"]).text
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard manifest.gitVersion == gitVersion else {
      throw BenchmarkError.fixtureMismatch(
        "Fixture Git version \(manifest.gitVersion) does not match \(gitVersion)."
      )
    }

    _ = try graph(repositoryURL, gitExecutable)
    _ = try status(repositoryURL, gitExecutable)
    _ = try diff()

    var graphSamples: [Double] = []
    var statusSamples: [Double] = []
    var diffSamples: [Double] = []
    for _ in 0..<iterations {
      graphSamples.append(try elapsedMilliseconds { try graph(repositoryURL, gitExecutable) })
      statusSamples.append(try elapsedMilliseconds { try status(repositoryURL, gitExecutable) })
      diffSamples.append(try elapsedMilliseconds { try diff() })
    }

    return BenchmarkReport(
      environment: BenchmarkEnvironment(
        machine: machineIdentifier(),
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        gitVersion: gitVersion,
        fixtureID: manifest.fixtureID,
        iterations: iterations
      ),
      metrics: [
        BenchmarkMetric(name: "graph-first-200-cli-parse-layout", samples: graphSamples),
        BenchmarkMetric(name: "working-copy-status", samples: statusSamples),
        BenchmarkMetric(name: "diff-10k-parse", samples: diffSamples),
      ]
    )
  }

  public func compare(
    baseline: BenchmarkReport,
    candidate: BenchmarkReport,
    thresholdPercent: Double = 10
  ) -> BenchmarkComparison {
    let compatible =
      baseline.environment.machine == candidate.environment.machine
      && baseline.environment.operatingSystem == candidate.environment.operatingSystem
      && baseline.environment.gitVersion == candidate.environment.gitVersion
      && baseline.environment.fixtureID == candidate.environment.fixtureID
      && baseline.environment.iterations == candidate.environment.iterations
    guard compatible else {
      return BenchmarkComparison(
        compatibleEnvironment: false,
        thresholdPercent: thresholdPercent,
        regressions: []
      )
    }

    let baselineMetrics = Dictionary(
      uniqueKeysWithValues: baseline.metrics.map { ($0.name, $0) }
    )
    let regressions = candidate.metrics.compactMap { metric -> BenchmarkRegression? in
      guard let reference = baselineMetrics[metric.name], reference.p95 > 0 else { return nil }
      let change = ((metric.p95 - reference.p95) / reference.p95) * 100
      guard change > thresholdPercent else { return nil }
      return BenchmarkRegression(
        metric: metric.name,
        baselineP95: reference.p95,
        candidateP95: metric.p95,
        changePercent: change
      )
    }
    return BenchmarkComparison(
      compatibleEnvironment: true,
      thresholdPercent: thresholdPercent,
      regressions: regressions
    )
  }

  private func graph(_ repositoryURL: URL, _ git: URL) throws {
    let format = "%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00"
    let result = try command(
      git,
      [
        "-C", repositoryURL.path, "log", "--date-order", "--all", "-n", "200",
        "--format=\(format)",
      ]
    )
    let parsed = try HistoryParser().parse(Array(result.data))
    let commits = parsed.map {
      CommitSummary(
        oid: $0.oid,
        parentOIDs: $0.parentOIDs,
        authorName: $0.authorName,
        authorEmail: $0.authorEmail,
        authoredAt: Date(timeIntervalSince1970: TimeInterval($0.authoredAtUnixSeconds)),
        subject: $0.subject
      )
    }
    var allocator = GraphLaneAllocator()
    _ = allocator.append(commits)
  }

  private func status(_ repositoryURL: URL, _ git: URL) throws {
    _ = try command(
      git,
      [
        "-C", repositoryURL.path, "status", "--porcelain=v2", "-z",
        "--untracked-files=all",
      ]
    )
  }

  private func diff() throws {
    var text = """
      diff --git a/benchmark.txt b/benchmark.txt
      --- a/benchmark.txt
      +++ b/benchmark.txt
      @@ -1,10000 +1,10000 @@

      """
    text.reserveCapacity(220_000)
    for index in 0..<10_000 {
      text += index.isMultiple(of: 10) ? "+changed \(index)\n" : " context \(index)\n"
    }
    _ = try UnifiedDiffParser().parse(
      Array(text.utf8),
      path: GitPath("benchmark.txt"),
      source: .unstaged
    )
  }

  private func elapsedMilliseconds(_ operation: () throws -> Void) rethrows -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    try operation()
    let duration = start.duration(to: clock.now)
    return Double(duration.components.seconds) * 1_000
      + Double(duration.components.attoseconds) / 1_000_000_000_000_000
  }

  private func command(_ executable: URL, _ arguments: [String]) throws -> (
    data: Data, text: String
  ) {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = try output.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw BenchmarkError.commandFailed(
        command: ([executable.path] + arguments).joined(separator: " "),
        status: process.terminationStatus,
        output: text
      )
    }
    return (data, text)
  }

  private func machineIdentifier() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var value = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &value, &size, nil, 0)
    let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}
