import Foundation
import Subprocess

public struct GitCommand: Hashable, Sendable {
  public let arguments: [[UInt8]]
  public let workingDirectory: URL?
  public let environmentOverrides: [String: String?]
  public let outputLimit: Int
  public let timeout: Duration

  public init(
    arguments: [String],
    workingDirectory: URL? = nil,
    environmentOverrides: [String: String?] = [:],
    outputLimit: Int = 16 * 1024 * 1024,
    timeout: Duration = .seconds(60)
  ) {
    self.init(
      rawArguments: arguments.map { Array($0.utf8) },
      workingDirectory: workingDirectory,
      environmentOverrides: environmentOverrides,
      outputLimit: outputLimit,
      timeout: timeout
    )
  }

  public init(
    rawArguments: [[UInt8]],
    workingDirectory: URL? = nil,
    environmentOverrides: [String: String?] = [:],
    outputLimit: Int = 16 * 1024 * 1024,
    timeout: Duration = .seconds(60)
  ) {
    self.arguments = rawArguments
    self.workingDirectory = workingDirectory
    self.environmentOverrides = environmentOverrides
    self.outputLimit = outputLimit
    self.timeout = timeout
  }

  public var redactedDescription: String {
    arguments
      .map { String(decoding: $0, as: UTF8.self) }
      .map(Self.redact)
      .joined(separator: " ")
  }

  private static func redact(_ argument: String) -> String {
    guard let separator = argument.firstIndex(of: "=") else { return argument }
    let key = argument[..<separator].lowercased()
    if key.contains("token") || key.contains("password") || key.contains("authorization") {
      return "\(argument[..<separator])=<redacted>"
    }
    return argument
  }
}

public struct GitProcessResult: Hashable, Sendable {
  public enum Termination: Hashable, Sendable {
    case exited(Int32)
    case signaled(Int32)
  }

  public let termination: Termination
  public let standardOutput: [UInt8]
  public let standardError: [UInt8]
  public let duration: Duration

  public init(
    termination: Termination,
    standardOutput: [UInt8],
    standardError: [UInt8],
    duration: Duration
  ) {
    self.termination = termination
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.duration = duration
  }

  public var succeeded: Bool {
    termination == .exited(0)
  }

  public var errorDescription: String {
    String(decoding: standardError, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public enum GitProcessError: Error, Sendable, Equatable {
  case timedOut(Duration)
  case launchFailed(String)
}

public protocol GitProcessRunning: Sendable {
  func run(_ command: GitCommand) async throws -> GitProcessResult
}

public struct SwiftSubprocessRunner: GitProcessRunning {
  public let executableURL: URL

  public init(executableURL: URL) {
    self.executableURL = executableURL
  }

  public func run(_ command: GitCommand) async throws -> GitProcessResult {
    let clock = ContinuousClock()
    let started = clock.now

    return try await withThrowingTaskGroup(of: GitProcessResult.self) { group in
      group.addTask {
        var platformOptions = PlatformOptions()
        platformOptions.createSession = true
        platformOptions.teardownSequence = [
          .send(
            signal: .interrupt,
            toProcessGroup: true,
            allowedDurationToNextStep: .seconds(1)
          ),
          .gracefulShutDown(
            toProcessGroup: true,
            allowedDurationToNextStep: .seconds(2)
          ),
        ]

        let environment = Environment.inherit.updating(
          Dictionary(
            uniqueKeysWithValues: ([
              "LC_ALL": "C",
              "LANG": "C",
              "GIT_TERMINAL_PROMPT": "0",
            ] as [String: String?])
            .merging(command.environmentOverrides) { _, commandValue in commandValue }
            .map { (Environment.Key(rawValue: $0.key)!, $0.value) }
          )
        )

        do {
          let result = try await Subprocess.run(
            .path(.init(self.executableURL.path)),
            arguments: Arguments(command.arguments),
            environment: environment,
            workingDirectory: command.workingDirectory.map { .init($0.path) },
            platformOptions: platformOptions,
            output: .bytes(limit: command.outputLimit),
            error: .bytes(limit: command.outputLimit)
          )

          let termination: GitProcessResult.Termination
          switch result.terminationStatus {
          case .exited(let code):
            termination = .exited(code)
          case .signaled(let signal):
            termination = .signaled(signal)
          }

          return GitProcessResult(
            termination: termination,
            standardOutput: result.standardOutput,
            standardError: result.standardError,
            duration: started.duration(to: clock.now)
          )
        } catch {
          throw GitProcessError.launchFailed(String(describing: error))
        }
      }

      group.addTask {
        try await Task.sleep(for: command.timeout)
        try Task.checkCancellation()
        throw GitProcessError.timedOut(command.timeout)
      }

      guard let first = try await group.next() else {
        throw GitProcessError.launchFailed("Subprocess task group returned no result")
      }
      group.cancelAll()
      return first
    }
  }
}
