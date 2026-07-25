import Foundation

public struct FixtureGenerator: Sendable {
  public init() {}

  @discardableResult
  public func generate(
    profile: FixtureProfile,
    at repositoryURL: URL,
    gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git")
  ) throws -> FixtureManifest {
    guard profile.commits > 0, profile.references > 0, profile.files > 0,
      profile.wipFiles >= 0
    else {
      throw BenchmarkError.invalidArguments("Fixture counts must be positive.")
    }

    let fileManager = FileManager.default
    let resolvedRepositoryURL = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
    if fileManager.fileExists(atPath: resolvedRepositoryURL.path) {
      let existingManifest = resolvedRepositoryURL.appendingPathComponent(
        ".git/current-benchmark.json"
      )
      guard fileManager.fileExists(atPath: existingManifest.path) else {
        throw BenchmarkError.fixtureMismatch(
          "Refusing to replace a directory that is not a Current benchmark fixture: "
            + resolvedRepositoryURL.path
        )
      }
      try fileManager.removeItem(at: resolvedRepositoryURL)
    }
    try fileManager.createDirectory(
      at: resolvedRepositoryURL,
      withIntermediateDirectories: true
    )
    _ = try run(
      gitExecutable,
      ["-c", "init.defaultBranch=main", "init", resolvedRepositoryURL.path]
    )

    let importLog = resolvedRepositoryURL.appendingPathComponent(
      ".git/current-fast-import.log"
    )
    fileManager.createFile(atPath: importLog.path, contents: nil)
    let logHandle = try FileHandle(forWritingTo: importLog)
    defer { try? logHandle.close() }

    let process = Process()
    process.executableURL = gitExecutable
    process.arguments = ["-C", resolvedRepositoryURL.path, "fast-import", "--quiet"]
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = logHandle
    process.standardError = logHandle
    try process.run()

    do {
      let writer = input.fileHandleForWriting
      try write("blob\nmark :1\ndata 24\nCurrent benchmark data\n\n", to: writer)
      var previousMark: Int?
      let baseTimestamp = 1_700_000_000
      for commitIndex in 0..<profile.commits {
        let mark = commitIndex + 2
        let message = "benchmark commit \(commitIndex)"
        try write("commit refs/heads/main\n", to: writer)
        try write("mark :\(mark)\n", to: writer)
        try write(
          "author Current Benchmark <benchmark@example.invalid> \(baseTimestamp + commitIndex) +0000\n",
          to: writer
        )
        try write(
          "committer Current Benchmark <benchmark@example.invalid> \(baseTimestamp + commitIndex) +0000\n",
          to: writer
        )
        try write("data \(message.utf8.count)\n\(message)\n", to: writer)
        if let previousMark {
          try write("from :\(previousMark)\n", to: writer)
        }

        if commitIndex == 0 {
          for fileIndex in 0..<profile.files {
            try write(
              "M 100644 :1 benchmark/file-\(padded(fileIndex, width: 7)).txt\n",
              to: writer
            )
          }
        } else {
          let fileIndex = commitIndex % profile.files
          try write(
            "M 100644 :1 benchmark/file-\(padded(fileIndex, width: 7)).txt\n",
            to: writer
          )
        }
        try write("\n", to: writer)
        previousMark = mark
      }

      guard let tipMark = previousMark else {
        throw BenchmarkError.fixtureMismatch("Fixture did not create a commit.")
      }
      if profile.references > 1 {
        for referenceIndex in 1..<profile.references {
          try write(
            "reset refs/tags/benchmark-\(padded(referenceIndex, width: 5))\n",
            to: writer
          )
          try write("from :\(tipMark)\n\n", to: writer)
        }
      }
      try writer.close()
    } catch {
      try? input.fileHandleForWriting.close()
      process.terminate()
      process.waitUntilExit()
      throw error
    }

    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let output = (try? String(contentsOf: importLog, encoding: .utf8)) ?? ""
      throw BenchmarkError.commandFailed(
        command: "git fast-import",
        status: process.terminationStatus,
        output: output
      )
    }

    for index in 0..<profile.wipFiles {
      let directory = resolvedRepositoryURL.appendingPathComponent(
        "working-copy/batch-\(padded(index / 1_000, width: 3))",
        isDirectory: true
      )
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("wip \(index)\n".utf8).write(
        to: directory.appendingPathComponent("wip-\(padded(index, width: 7)).txt")
      )
    }

    let gitVersion = try run(gitExecutable, ["--version"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let manifest = FixtureManifest(profile: profile, gitVersion: gitVersion)
    let manifestURL = resolvedRepositoryURL.appendingPathComponent(
      ".git/current-benchmark.json"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    return manifest
  }

  private func run(_ executable: URL, _ arguments: [String]) throws -> String {
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
    return text
  }

  private func write(_ string: String, to handle: FileHandle) throws {
    try handle.write(contentsOf: Data(string.utf8))
  }

  private func padded(_ value: Int, width: Int) -> String {
    String(format: "%0\(width)d", value)
  }
}
