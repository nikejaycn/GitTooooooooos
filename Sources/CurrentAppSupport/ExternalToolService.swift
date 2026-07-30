import CurrentDomain
import Foundation

public enum ExternalToolServiceError: Error, Sendable, Equatable, LocalizedError {
  case notConfigured(String)
  case notFound(String)
  case failed(String, Int32)

  public var errorDescription: String? {
    switch self {
    case .notConfigured(let role):
      "Choose an external \(role) tool in Settings first."
    case .notFound(let message):
      message
    case .failed(let tool, let status):
      "\(tool) exited with status \(status). The conflict was not marked resolved."
    }
  }
}

/// Resolves, prepares, and launches external diff and merge tools.
///
/// The service owns temporary-file security, executable discovery, argument planning, and
/// process lifetime so application coordinators only exchange repository contents.
@MainActor
public final class ExternalToolService {
  private let fileManager: FileManager
  private let temporaryDirectory: URL
  private var detachedProcesses: [UUID: Process] = [:]

  public init(
    fileManager: FileManager = .default,
    temporaryDirectory: URL? = nil
  ) {
    self.fileManager = fileManager
    self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
  }

  public func openDiff(
    tool: ExternalTool,
    customPath: String,
    path: String,
    before: [UInt8]?,
    after: [UInt8]?
  ) throws {
    let executable = try resolveExecutable(tool, customPath: customPath, role: "diff")
    let directory = try makeInvocationDirectory()
    let fileName = safeFileName(path)
    let beforeURL = directory.appendingPathComponent("Before-\(fileName)")
    let afterURL = directory.appendingPathComponent("After-\(fileName)")
    try Data(before ?? []).write(to: beforeURL, options: .atomic)
    try Data(after ?? []).write(to: afterURL, options: .atomic)
    let arguments = ExternalToolInvocationPlanner.diffArguments(
      tool: tool,
      before: beforeURL.path,
      after: afterURL.path
    )
    try launchDetached(executable: executable, arguments: arguments)
  }

  public func merge(
    tool: ExternalTool,
    customPath: String,
    path: String,
    base: [UInt8]?,
    ours: [UInt8]?,
    theirs: [UInt8]?,
    workingTree: [UInt8]
  ) async throws -> [UInt8] {
    let executable = try resolveExecutable(tool, customPath: customPath, role: "merge")
    let directory = try makeInvocationDirectory()
    let fileName = safeFileName(path)
    let baseURL = directory.appendingPathComponent("Base-\(fileName)")
    let oursURL = directory.appendingPathComponent("Ours-\(fileName)")
    let theirsURL = directory.appendingPathComponent("Theirs-\(fileName)")
    let resultURL = directory.appendingPathComponent("Result-\(fileName)")
    try Data(base ?? []).write(to: baseURL, options: .atomic)
    try Data(ours ?? []).write(to: oursURL, options: .atomic)
    try Data(theirs ?? []).write(to: theirsURL, options: .atomic)
    try Data(workingTree).write(to: resultURL, options: .atomic)

    let arguments = ExternalToolInvocationPlanner.mergeArguments(
      tool: tool,
      base: baseURL.path,
      ours: oursURL.path,
      theirs: theirsURL.path,
      result: resultURL.path
    )
    let status = try await run(executable: executable, arguments: arguments)
    guard status == 0 else {
      throw ExternalToolServiceError.failed(tool.title, status)
    }
    return Array(try Data(contentsOf: resultURL))
  }

  public func resolveExecutable(
    _ tool: ExternalTool,
    customPath: String,
    role: String
  ) throws -> URL {
    let candidates: [String]
    switch tool {
    case .none:
      throw ExternalToolServiceError.notConfigured(role)
    case .fileMerge:
      candidates = ["/usr/bin/opendiff"]
    case .kaleidoscope:
      candidates = [
        "/opt/homebrew/bin/ksdiff",
        "/usr/local/bin/ksdiff",
        "/Applications/Kaleidoscope.app/Contents/MacOS/ksdiff",
      ]
    case .beyondCompare:
      candidates = [
        "/Applications/Beyond Compare.app/Contents/MacOS/bcomp",
        "/opt/homebrew/bin/bcomp",
        "/usr/local/bin/bcomp",
      ]
    case .custom:
      candidates = [customPath]
    }

    for path in candidates where !path.isEmpty {
      var isDirectory: ObjCBool = false
      if fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
        !isDirectory.boolValue,
        fileManager.isExecutableFile(atPath: path)
      {
        return URL(fileURLWithPath: path).standardizedFileURL
      }
    }
    if tool == .custom {
      throw ExternalToolServiceError.notFound(
        "The custom executable is missing or not executable. Choose a valid file in Settings."
      )
    }
    throw ExternalToolServiceError.notFound(
      "\(tool.title) could not be found. Install its command-line tool or choose another tool in Settings."
    )
  }

  private func makeInvocationDirectory() throws -> URL {
    let root =
      temporaryDirectory
      .appendingPathComponent("GitCurrentExternalTools", isDirectory: true)
    try fileManager.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    return directory
  }

  private func safeFileName(_ path: String) -> String {
    let last = URL(fileURLWithPath: path).lastPathComponent
    let cleaned = last.replacingOccurrences(
      of: #"[^A-Za-z0-9._-]"#,
      with: "_",
      options: .regularExpression
    )
    return cleaned.isEmpty ? "File" : String(cleaned.prefix(120))
  }

  private func launchDetached(executable: URL, arguments: [String]) throws {
    let id = UUID()
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.terminationHandler = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.detachedProcesses[id] = nil
      }
    }
    detachedProcesses[id] = process
    do {
      try process.run()
    } catch {
      detachedProcesses[id] = nil
      throw error
    }
  }

  private func run(executable: URL, arguments: [String]) async throws -> Int32 {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = executable
      process.arguments = arguments
      process.terminationHandler = { completed in
        continuation.resume(returning: completed.terminationStatus)
      }
      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}
