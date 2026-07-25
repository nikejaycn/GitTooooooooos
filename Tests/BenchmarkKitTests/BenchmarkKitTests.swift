import BenchmarkKit
import Foundation
import Testing

@Suite("Deterministic benchmark fixtures and gates")
struct BenchmarkKitTests {
  @Test("PRD scale profiles are frozen")
  func profiles() {
    #expect(
      BenchmarkScale.s.profile
        == FixtureProfile(
          scale: .s,
          commits: 1_000,
          references: 100,
          files: 2_000,
          wipFiles: 0
        ))
    #expect(BenchmarkScale.m.profile.commits == 50_000)
    #expect(BenchmarkScale.m.profile.references == 1_000)
    #expect(BenchmarkScale.m.profile.files == 20_000)
    #expect(BenchmarkScale.l.profile.commits == 500_000)
    #expect(BenchmarkScale.l.profile.references == 5_000)
    #expect(BenchmarkScale.l.profile.files == 250_000)
    #expect(BenchmarkScale.l.profile.wipFiles == 5_000)
  }

  @Test("Small generated fixture is reproducible and measurable")
  func integration() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-benchmark-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = FixtureProfile(
      scale: .s,
      commits: 12,
      references: 4,
      files: 8,
      wipFiles: 3
    )

    let manifest = try FixtureGenerator().generate(profile: profile, at: root)
    #expect(manifest.fixtureID == profile.fixtureID)
    #expect(try git(["-C", root.path, "rev-list", "--count", "HEAD"]) == "12")
    #expect(try git(["-C", root.path, "show-ref"]).split(separator: "\n").count == 4)
    #expect(
      try git(["-C", root.path, "ls-tree", "-r", "--name-only", "HEAD"])
        .split(separator: "\n").count == 8
    )

    let report = try BenchmarkRunner().run(repositoryURL: root, iterations: 3)
    #expect(report.environment.fixtureID == profile.fixtureID)
    #expect(report.metrics.count == 3)
    #expect(report.metrics.allSatisfy { $0.samples.count == 3 && $0.p95 >= $0.p50 })
  }

  @Test("Gate rejects incompatible environments and regressions over ten percent")
  func comparison() {
    let environment = BenchmarkEnvironment(
      machine: "Mac",
      operatingSystem: "macOS",
      gitVersion: "git version 1",
      fixtureID: "fixture",
      iterations: 5
    )
    let baseline = BenchmarkReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      environment: environment,
      metrics: [BenchmarkMetric(name: "graph", samples: [100, 100, 100])]
    )
    let regression = BenchmarkReport(
      generatedAt: Date(timeIntervalSince1970: 1),
      environment: environment,
      metrics: [BenchmarkMetric(name: "graph", samples: [111, 111, 111])]
    )
    let result = BenchmarkRunner().compare(baseline: baseline, candidate: regression)
    #expect(!result.passed)
    #expect(result.regressions.count == 1)

    let incompatible = BenchmarkReport(
      environment: BenchmarkEnvironment(
        machine: "Other Mac",
        operatingSystem: "macOS",
        gitVersion: "git version 1",
        fixtureID: "fixture",
        iterations: 5
      ),
      metrics: baseline.metrics
    )
    #expect(!BenchmarkRunner().compare(baseline: baseline, candidate: incompatible).passed)
  }

  @Test("Generator refuses to replace an unrelated directory")
  func replacementBoundary() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("current-not-a-fixture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sentinel = root.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: sentinel)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: BenchmarkError.self) {
      try FixtureGenerator().generate(
        profile: FixtureProfile(
          scale: .s,
          commits: 1,
          references: 1,
          files: 1,
          wipFiles: 0
        ),
        at: root
      )
    }
    #expect(FileManager.default.fileExists(atPath: sentinel.path))
  }

  private func git(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = try output.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw BenchmarkError.commandFailed(
        command: arguments.joined(separator: " "),
        status: process.terminationStatus,
        output: String(decoding: data, as: UTF8.self)
      )
    }
    return String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
