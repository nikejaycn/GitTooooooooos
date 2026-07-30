import AppKit
import Foundation

public struct CurrentLaunchRequest: Equatable, Sendable {
  public let repositoryURL: URL
  public let applicationURL: URL?

  public init(repositoryURL: URL, applicationURL: URL?) {
    self.repositoryURL = repositoryURL
    self.applicationURL = applicationURL
  }

  public static func parse(
    _ arguments: [String],
    currentDirectoryURL: URL
  ) throws -> CurrentLaunchRequest {
    var values = arguments
    if values.first == "open" {
      values.removeFirst()
    }
    var applicationURL: URL?
    if let index = values.firstIndex(of: "--app") {
      guard index + 1 < values.count else {
        throw CurrentLauncherError.invalidArguments("--app requires a GitCurrent.app path.")
      }
      applicationURL = fileURL(values[index + 1], relativeTo: currentDirectoryURL)
      values.removeSubrange(index...(index + 1))
    }
    guard values.count <= 1 else {
      throw CurrentLauncherError.invalidArguments(usage)
    }
    let repositoryURL =
      values.first.map { fileURL($0, relativeTo: currentDirectoryURL) }
      ?? currentDirectoryURL.standardizedFileURL
    return CurrentLaunchRequest(
      repositoryURL: repositoryURL,
      applicationURL: applicationURL
    )
  }

  private static func fileURL(_ path: String, relativeTo base: URL) -> URL {
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path).standardizedFileURL
    }
    return base.appendingPathComponent(path).standardizedFileURL
  }

  public static let usage = """
    usage: current open [repository] [--app /path/to/GitCurrent.app]
           current [repository] [--app /path/to/GitCurrent.app]
    """
}

public enum CurrentLauncherError: Error, LocalizedError {
  case invalidArguments(String)
  case repositoryNotDirectory(String)
  case applicationNotFound
  case launchFailed

  public var errorDescription: String? {
    switch self {
    case .invalidArguments(let message), .repositoryNotDirectory(let message):
      message
    case .applicationNotFound:
      "GitCurrent.app was not found. Install it or pass --app /path/to/GitCurrent.app."
    case .launchFailed:
      "macOS could not open the repository in GitCurrent."
    }
  }
}

@MainActor
public struct CurrentLauncher {
  public init() {}

  public func launch(_ request: CurrentLaunchRequest) async throws {
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: request.repositoryURL.path,
        isDirectory: &isDirectory
      ),
      isDirectory.boolValue
    else {
      throw CurrentLauncherError.repositoryNotDirectory(
        "Repository path is not a directory: \(request.repositoryURL.path)"
      )
    }
    let applicationURL =
      request.applicationURL
      ?? NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.fun2ex.Current"
      )
    guard let applicationURL else {
      throw CurrentLauncherError.applicationNotFound
    }
    var isAppDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: applicationURL.path,
        isDirectory: &isAppDirectory
      ),
      isAppDirectory.boolValue,
      applicationURL.pathExtension == "app"
    else {
      throw CurrentLauncherError.applicationNotFound
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    try await NSWorkspace.shared.open(
      [request.repositoryURL],
      withApplicationAt: applicationURL,
      configuration: configuration
    )
  }
}
