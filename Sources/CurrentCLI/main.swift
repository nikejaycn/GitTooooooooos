import CurrentCLIKit
import Foundation

@main
enum CurrentCLI {
  @MainActor
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] {
      print(CurrentLaunchRequest.usage)
      return
    }
    do {
      let request = try CurrentLaunchRequest.parse(
        arguments,
        currentDirectoryURL: URL(
          fileURLWithPath: FileManager.default.currentDirectoryPath,
          isDirectory: true
        )
      )
      try await CurrentLauncher().launch(request)
    } catch {
      FileHandle.standardError.write(
        Data("current: \(error.localizedDescription)\n".utf8)
      )
      exit(1)
    }
  }
}
