import Foundation

public enum BenchmarkScale: String, Codable, CaseIterable, Sendable {
  case s
  case m
  case l

  public var profile: FixtureProfile {
    switch self {
    case .s:
      FixtureProfile(scale: self, commits: 1_000, references: 100, files: 2_000, wipFiles: 0)
    case .m:
      FixtureProfile(scale: self, commits: 50_000, references: 1_000, files: 20_000, wipFiles: 0)
    case .l:
      FixtureProfile(
        scale: self,
        commits: 500_000,
        references: 5_000,
        files: 250_000,
        wipFiles: 5_000
      )
    }
  }
}

public struct FixtureProfile: Codable, Equatable, Sendable {
  public let scale: BenchmarkScale
  public let commits: Int
  public let references: Int
  public let files: Int
  public let wipFiles: Int

  public init(
    scale: BenchmarkScale,
    commits: Int,
    references: Int,
    files: Int,
    wipFiles: Int
  ) {
    self.scale = scale
    self.commits = commits
    self.references = references
    self.files = files
    self.wipFiles = wipFiles
  }

  public var fixtureID: String {
    let input = "\(scale.rawValue):\(commits):\(references):\(files):\(wipFiles):v2"
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in input.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(format: "current-%@-%016llx", scale.rawValue, hash)
  }
}

public struct FixtureManifest: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let fixtureID: String
  public let profile: FixtureProfile
  public let gitVersion: String

  public init(profile: FixtureProfile, gitVersion: String) {
    schemaVersion = 2
    fixtureID = profile.fixtureID
    self.profile = profile
    self.gitVersion = gitVersion
  }
}

public struct BenchmarkMetric: Codable, Equatable, Sendable {
  public let name: String
  public let unit: String
  public let samples: [Double]
  public let p50: Double
  public let p95: Double

  public init(name: String, unit: String = "ms", samples: [Double]) {
    self.name = name
    self.unit = unit
    self.samples = samples
    let sorted = samples.sorted()
    p50 = Self.percentile(0.50, in: sorted)
    p95 = Self.percentile(0.95, in: sorted)
  }

  private static func percentile(_ percentile: Double, in values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let index = Int((Double(values.count - 1) * percentile).rounded(.up))
    return values[min(index, values.count - 1)]
  }
}

public struct BenchmarkEnvironment: Codable, Equatable, Sendable {
  public let machine: String
  public let operatingSystem: String
  public let gitVersion: String
  public let fixtureID: String
  public let iterations: Int

  public init(
    machine: String,
    operatingSystem: String,
    gitVersion: String,
    fixtureID: String,
    iterations: Int
  ) {
    self.machine = machine
    self.operatingSystem = operatingSystem
    self.gitVersion = gitVersion
    self.fixtureID = fixtureID
    self.iterations = iterations
  }
}

public struct BenchmarkReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let environment: BenchmarkEnvironment
  public let metrics: [BenchmarkMetric]

  public init(
    generatedAt: Date = Date(),
    environment: BenchmarkEnvironment,
    metrics: [BenchmarkMetric]
  ) {
    schemaVersion = 1
    self.generatedAt = generatedAt
    self.environment = environment
    self.metrics = metrics
  }
}

public struct BenchmarkRegression: Codable, Equatable, Sendable {
  public let metric: String
  public let baselineP95: Double
  public let candidateP95: Double
  public let changePercent: Double
}

public struct BenchmarkComparison: Codable, Equatable, Sendable {
  public let compatibleEnvironment: Bool
  public let thresholdPercent: Double
  public let regressions: [BenchmarkRegression]

  public var passed: Bool {
    compatibleEnvironment && regressions.isEmpty
  }
}

public enum BenchmarkError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case commandFailed(command: String, status: Int32, output: String)
  case fixtureMismatch(String)
  case incompatibleBaseline
  case regressions([BenchmarkRegression])

  public var description: String {
    switch self {
    case .invalidArguments(let message), .fixtureMismatch(let message):
      message
    case .commandFailed(let command, let status, let output):
      "\(command) exited \(status): \(output)"
    case .incompatibleBaseline:
      "Baseline and candidate must use the same machine, OS, Git, fixture, and iteration count."
    case .regressions(let regressions):
      regressions.map { "\($0.metric): \(String(format: "%.1f", $0.changePercent))%" }
        .joined(separator: ", ")
    }
  }
}
