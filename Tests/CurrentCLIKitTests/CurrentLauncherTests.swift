import CurrentCLIKit
import Foundation
import Testing

@Suite("Current CLI launcher")
struct CurrentLauncherTests {
  @Test("Defaults to the current directory")
  func currentDirectory() throws {
    let base = URL(fileURLWithPath: "/tmp/work", isDirectory: true)
    let request = try CurrentLaunchRequest.parse([], currentDirectoryURL: base)
    #expect(request.repositoryURL.path == "/tmp/work")
    #expect(request.applicationURL == nil)
  }

  @Test("Parses option-safe relative repository and explicit app paths")
  func explicitPaths() throws {
    let base = URL(fileURLWithPath: "/tmp/work", isDirectory: true)
    let request = try CurrentLaunchRequest.parse(
      ["open", "../repo with spaces", "--app", "/tmp/Build/GitCurrent.app"],
      currentDirectoryURL: base
    )
    #expect(request.repositoryURL.path == "/tmp/repo with spaces")
    #expect(request.applicationURL?.path == "/tmp/Build/GitCurrent.app")
  }

  @Test("Rejects extra arguments and missing option values")
  func invalidArguments() {
    let base = URL(fileURLWithPath: "/tmp", isDirectory: true)
    #expect(throws: CurrentLauncherError.self) {
      try CurrentLaunchRequest.parse(["one", "two"], currentDirectoryURL: base)
    }
    #expect(throws: CurrentLauncherError.self) {
      try CurrentLaunchRequest.parse(["--app"], currentDirectoryURL: base)
    }
  }
}
