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

    let loadedHistory = try history(
      repositoryURL,
      gitExecutable,
      offset: 0,
      limit: min(manifest.profile.commits, 50_000)
    )
    let workingCopyFixture = syntheticWorkingCopyChanges(count: 5_000)
    let workingCopyCatalog = WorkingCopyChangeCatalog(changes: workingCopyFixture)

    _ = try graph(repositoryURL, gitExecutable)
    _ = try status(repositoryURL, gitExecutable)
    _ = try diff()

    let graphDepths = [2, 10, 50, 250]
    let historyOffsets = [
      0,
      max(0, manifest.profile.commits / 2 - 100),
      max(0, manifest.profile.commits - 200),
    ]

    var graphSamples: [Double] = []
    var statusSamples: [Double] = []
    var diffSamples: [Double] = []
    var graphAppendSamples = Dictionary(
      uniqueKeysWithValues: graphDepths.map { ($0, [Double]()) }
    )
    var historyPageSamples = Dictionary(
      uniqueKeysWithValues: historyOffsets.indices.map { ($0, [Double]()) }
    )
    var workingCopyBuildSamples: [Double] = []
    var workingCopySearchSamples: [Double] = []
    for _ in 0..<iterations {
      graphSamples.append(try elapsedMilliseconds { try graph(repositoryURL, gitExecutable) })
      statusSamples.append(try elapsedMilliseconds { try status(repositoryURL, gitExecutable) })
      diffSamples.append(try elapsedMilliseconds { try diff() })
      for depth in graphDepths {
        graphAppendSamples[depth, default: []].append(
          graphPageAppendMilliseconds(loadedHistory, page: depth)
        )
      }
      for (index, offset) in historyOffsets.enumerated() {
        historyPageSamples[index, default: []].append(
          try elapsedMilliseconds {
            _ = try history(repositoryURL, gitExecutable, offset: offset, limit: 200)
          }
        )
      }
      workingCopyBuildSamples.append(
        elapsedMilliseconds {
          _ = WorkingCopyChangeCatalog(changes: workingCopyFixture)
        }
      )
      workingCopySearchSamples.append(
        elapsedMilliseconds {
          _ = workingCopyCatalog.filtered(query: "module42 file")
        }
      )
    }

    var metrics = [
      BenchmarkMetric(name: "graph-first-200-cli-parse-layout", samples: graphSamples),
      BenchmarkMetric(name: "working-copy-status-cli-parse-map-sort", samples: statusSamples),
      BenchmarkMetric(name: "working-copy-5k-catalog-build", samples: workingCopyBuildSamples),
      BenchmarkMetric(name: "working-copy-5k-cached-search", samples: workingCopySearchSamples),
      BenchmarkMetric(name: "diff-10k-parse", samples: diffSamples),
    ]
    metrics += graphDepths.map { depth in
      BenchmarkMetric(
        name: "graph-page-\(depth)-append-layout",
        samples: graphAppendSamples[depth] ?? []
      )
    }
    let historyPageNames = ["first", "middle", "deep"]
    metrics += historyOffsets.indices.map { index in
      BenchmarkMetric(
        name: "history-page-200-\(historyPageNames[index])-cli-parse",
        samples: historyPageSamples[index] ?? []
      )
    }

    return BenchmarkReport(
      environment: BenchmarkEnvironment(
        machine: machineIdentifier(),
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        gitVersion: gitVersion,
        fixtureID: manifest.fixtureID,
        iterations: iterations
      ),
      metrics: metrics
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
      && Set(baseline.metrics.map(\.name)) == Set(candidate.metrics.map(\.name))
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
    let commits = try history(repositoryURL, git, offset: 0, limit: 200)
    var allocator = GraphLaneAllocator()
    _ = allocator.append(commits)
  }

  private func history(
    _ repositoryURL: URL,
    _ git: URL,
    offset: Int,
    limit: Int
  ) throws -> [CommitSummary] {
    guard limit > 0 else { return [] }
    let format = "%x1e%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00"
    let result = try command(
      git,
      [
        "-C", repositoryURL.path, "log", "--topo-order", "--date-order", "--all",
        "--skip=\(max(0, offset))", "--max-count=\(limit)", "--format=\(format)",
      ]
    )
    return try HistoryParser().parse(Array(result.data)).map {
      CommitSummary(
        oid: $0.oid,
        parentOIDs: $0.parentOIDs,
        authorName: $0.authorName,
        authorEmail: $0.authorEmail,
        authoredAt: Date(timeIntervalSince1970: TimeInterval($0.authoredAtUnixSeconds)),
        subject: $0.subject
      )
    }
  }

  private func graphPageAppendMilliseconds(
    _ commits: [CommitSummary],
    page: Int
  ) -> Double {
    let pageSize = 200
    let prefixCount = min(max(0, (page - 1) * pageSize), commits.count)
    var session = GraphRowBuildSession()
    _ = session.reset(
      commits: Array(commits.prefix(prefixCount)),
      references: [],
      pinnedReferenceNames: [],
      workingCopyChangeCount: 0,
      generation: RepositoryGeneration(1)
    )
    let suffix = commits.dropFirst(prefixCount).prefix(pageSize)
    return elapsedMilliseconds {
      _ = session.append(commits: suffix)
    }
  }

  private func status(_ repositoryURL: URL, _ git: URL) throws {
    let result = try command(
      git,
      [
        "-C", repositoryURL.path, "status", "--porcelain=v2", "--branch", "-z",
        "--untracked-files=all",
      ]
    )
    let parsed = try PorcelainV2Parser().parse(result.data)
    _ = WorkingCopyChangeCatalog(changes: parsed.records.map(mapRecord))
  }

  private func mapRecord(_ record: PorcelainV2Record) -> FileChange {
    switch record {
    case .ordinary(let entry):
      FileChange(
        path: GitPath(rawBytes: entry.path),
        indexStatus: entry.indexStatus,
        worktreeStatus: entry.worktreeStatus,
        kind: changeKind(index: entry.indexStatus, worktree: entry.worktreeStatus)
      )
    case .renamedOrCopied(let entry):
      FileChange(
        path: GitPath(rawBytes: entry.tracked.path),
        originalPath: GitPath(rawBytes: entry.originalPath),
        indexStatus: entry.tracked.indexStatus,
        worktreeStatus: entry.tracked.worktreeStatus,
        kind: entry.score.first == "C" ? .copied : .renamed
      )
    case .unmerged(let entry):
      FileChange(
        path: GitPath(rawBytes: entry.path),
        indexStatus: entry.indexStatus,
        worktreeStatus: entry.worktreeStatus,
        kind: .unmerged
      )
    case .untracked(let path):
      FileChange(
        path: GitPath(rawBytes: path), indexStatus: 63, worktreeStatus: 63, kind: .untracked
      )
    case .ignored(let path):
      FileChange(
        path: GitPath(rawBytes: path), indexStatus: 33, worktreeStatus: 33, kind: .ignored
      )
    }
  }

  private func changeKind(index: UInt8, worktree: UInt8) -> FileChangeKind {
    for byte in [index, worktree] where byte != 46 {
      switch byte {
      case 65: return .added
      case 77: return .modified
      case 68: return .deleted
      case 82: return .renamed
      case 67: return .copied
      case 84: return .typeChanged
      case 85: return .unmerged
      default: continue
      }
    }
    return .unknown
  }

  private func syntheticWorkingCopyChanges(count: Int) -> [FileChange] {
    (0..<count).map { index in
      FileChange(
        path: GitPath(
          String(format: "Sources/Module%02d/File%05d.swift", index % 100, index)
        ),
        indexStatus: index.isMultiple(of: 3) ? 77 : 46,
        worktreeStatus: index.isMultiple(of: 3) ? 46 : 77,
        kind: .modified
      )
    }
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
