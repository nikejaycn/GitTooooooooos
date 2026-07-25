import BenchmarkKit
import Foundation

@main
enum CurrentBenchmarkCLI {
  static func main() {
    do {
      try execute(Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func execute(_ arguments: [String]) throws {
    guard let command = arguments.first else {
      throw BenchmarkError.invalidArguments(usage)
    }
    switch command {
    case "generate":
      let options = try Options(Array(arguments.dropFirst()))
      guard let scale = BenchmarkScale(rawValue: try options.required("scale")) else {
        throw BenchmarkError.invalidArguments("--scale must be s, m, or l.")
      }
      let destination = URL(fileURLWithPath: try options.required("output"))
      let manifest = try FixtureGenerator().generate(
        profile: scale.profile,
        at: destination,
        gitExecutable: options.gitExecutable
      )
      try printJSON(manifest)
    case "run":
      let options = try Options(Array(arguments.dropFirst()))
      let repository = URL(fileURLWithPath: try options.required("repository"))
      let iterations = Int(options.value("iterations") ?? "7") ?? 0
      let report = try BenchmarkRunner().run(
        repositoryURL: repository,
        iterations: iterations,
        gitExecutable: options.gitExecutable
      )
      if let output = options.value("output") {
        try encoded(report).write(to: URL(fileURLWithPath: output), options: .atomic)
      }
      try printJSON(report)
    case "compare":
      let options = try Options(Array(arguments.dropFirst()))
      let baseline = try decodeReport(options.required("baseline"))
      let candidate = try decodeReport(options.required("candidate"))
      let threshold = Double(options.value("threshold") ?? "10") ?? 10
      let comparison = BenchmarkRunner().compare(
        baseline: baseline,
        candidate: candidate,
        thresholdPercent: threshold
      )
      try printJSON(comparison)
      guard comparison.compatibleEnvironment else {
        throw BenchmarkError.incompatibleBaseline
      }
      guard comparison.regressions.isEmpty else {
        throw BenchmarkError.regressions(comparison.regressions)
      }
    default:
      throw BenchmarkError.invalidArguments(usage)
    }
  }

  private static func decodeReport(_ path: String) throws -> BenchmarkReport {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      BenchmarkReport.self,
      from: Data(contentsOf: URL(fileURLWithPath: path))
    )
  }

  private static func printJSON<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try encoded(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
  }

  private static let usage = """
    current-benchmark generate --scale s|m|l --output PATH [--git PATH]
    current-benchmark run --repository PATH [--iterations 7] [--output REPORT] [--git PATH]
    current-benchmark compare --baseline REPORT --candidate REPORT [--threshold 10]
    """
}

private struct Options {
  private let values: [String: String]

  init(_ arguments: [String]) throws {
    guard arguments.count.isMultiple(of: 2) else {
      throw BenchmarkError.invalidArguments("Options must be --name value pairs.")
    }
    var parsed: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      let key = arguments[index]
      guard key.hasPrefix("--") else {
        throw BenchmarkError.invalidArguments("Unexpected option \(key).")
      }
      parsed[String(key.dropFirst(2))] = arguments[index + 1]
      index += 2
    }
    values = parsed
  }

  func value(_ name: String) -> String? {
    values[name]
  }

  func required(_ name: String) throws -> String {
    guard let value = values[name], !value.isEmpty else {
      throw BenchmarkError.invalidArguments("Missing --\(name).")
    }
    return value
  }

  var gitExecutable: URL {
    URL(fileURLWithPath: values["git"] ?? "/usr/bin/git")
  }
}
