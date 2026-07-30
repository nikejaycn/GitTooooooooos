import Foundation

public struct DiagnosticSystemReportMetadata: Codable, Hashable, Sendable {
  public let archiveName: String
  public let byteCount: Int64

  public init(archiveName: String, byteCount: Int64) {
    self.archiveName = archiveName
    self.byteCount = byteCount
  }
}

public struct DiagnosticOperationRecord: Codable, Hashable, Sendable {
  public let startedAt: Date
  public let finishedAt: Date?
  public let state: OperationActivityState
  public let title: String
  public let detail: String?
  public let durationMilliseconds: Int?

  public init(
    startedAt: Date,
    finishedAt: Date?,
    state: OperationActivityState,
    title: String,
    detail: String?,
    durationMilliseconds: Int?
  ) {
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.state = state
    self.title = title
    self.detail = detail
    self.durationMilliseconds = durationMilliseconds
  }
}

public struct DiagnosticPerformanceSummary: Codable, Hashable, Sendable {
  public let operationCount: Int
  public let runningCount: Int
  public let succeededCount: Int
  public let failedCount: Int
  public let cancelledCount: Int
  public let averageDurationMilliseconds: Int?
  public let maximumDurationMilliseconds: Int?

  public init(
    operationCount: Int,
    runningCount: Int,
    succeededCount: Int,
    failedCount: Int,
    cancelledCount: Int,
    averageDurationMilliseconds: Int?,
    maximumDurationMilliseconds: Int?
  ) {
    self.operationCount = operationCount
    self.runningCount = runningCount
    self.succeededCount = succeededCount
    self.failedCount = failedCount
    self.cancelledCount = cancelledCount
    self.averageDurationMilliseconds = averageDurationMilliseconds
    self.maximumDurationMilliseconds = maximumDurationMilliseconds
  }
}

public struct DiagnosticBundleManifest: Codable, Hashable, Sendable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let appVersion: String
  public let appBuild: String
  public let operatingSystem: String
  public let architecture: String
  public let gitVersion: String?
  public let gitLFSVersion: String?
  public let gitSource: String
  public let hasOpenRepository: Bool
  public let loadedCommitCount: Int
  public let workingCopyChangeCount: Int
  public let automaticCollectionEnabled: Bool
  public let automaticUploadEnabled: Bool
  public let selectedSystemReports: [DiagnosticSystemReportMetadata]
  public let performance: DiagnosticPerformanceSummary

  public init(
    schemaVersion: Int = 1,
    generatedAt: Date,
    appVersion: String,
    appBuild: String,
    operatingSystem: String,
    architecture: String,
    gitVersion: String?,
    gitLFSVersion: String?,
    gitSource: String,
    hasOpenRepository: Bool,
    loadedCommitCount: Int,
    workingCopyChangeCount: Int,
    automaticCollectionEnabled: Bool = false,
    automaticUploadEnabled: Bool = false,
    selectedSystemReports: [DiagnosticSystemReportMetadata],
    performance: DiagnosticPerformanceSummary
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.operatingSystem = operatingSystem
    self.architecture = architecture
    self.gitVersion = gitVersion
    self.gitLFSVersion = gitLFSVersion
    self.gitSource = gitSource
    self.hasOpenRepository = hasOpenRepository
    self.loadedCommitCount = loadedCommitCount
    self.workingCopyChangeCount = workingCopyChangeCount
    self.automaticCollectionEnabled = automaticCollectionEnabled
    self.automaticUploadEnabled = automaticUploadEnabled
    self.selectedSystemReports = selectedSystemReports
    self.performance = performance
  }
}

public struct DiagnosticBundlePreview: Hashable, Sendable {
  public let manifest: DiagnosticBundleManifest
  public let operations: [DiagnosticOperationRecord]

  public init(
    manifest: DiagnosticBundleManifest,
    operations: [DiagnosticOperationRecord]
  ) {
    self.manifest = manifest
    self.operations = operations
  }

  public func encodedFiles() throws -> [String: Data] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return [
      "manifest.json": try encoder.encode(manifest),
      "operations.json": try encoder.encode(operations),
    ]
  }

  public func renderedPreview() -> String {
    do {
      let files = try encodedFiles()
      return ["manifest.json", "operations.json"]
        .compactMap { name in
          files[name]
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { "\(name)\n\($0)" }
        }
        .joined(separator: "\n\n")
    } catch {
      return "Unable to render diagnostic preview: \(error.localizedDescription)"
    }
  }
}

public enum DiagnosticBundleExportError: LocalizedError {
  case tooManySystemReports
  case invalidSystemReport
  case systemReportTooLarge
  case archiveFailed(Int32)

  public var errorDescription: String? {
    switch self {
    case .tooManySystemReports:
      "Choose at most five system reports."
    case .invalidSystemReport:
      "A selected system report is no longer a readable regular file."
    case .systemReportTooLarge:
      "Each selected system report must be 20 MB or smaller."
    case .archiveFailed(let status):
      "The system archive tool exited with status \(status)."
    }
  }
}

public enum DiagnosticBundleExporter {
  public static func export(
    preview: DiagnosticBundlePreview,
    selectedSystemReportURLs: [URL],
    to destinationURL: URL
  ) async throws {
    guard selectedSystemReportURLs.count <= 5 else {
      throw DiagnosticBundleExportError.tooManySystemReports
    }
    try await Task.detached(priority: .userInitiated) {
      let fileManager = FileManager.default
      let selectedReports = try selectedSystemReportURLs.map { url in
        let values = try url.resourceValues(
          forKeys: [.fileSizeKey, .isRegularFileKey]
        )
        guard values.isRegularFile == true, values.fileSize != nil else {
          throw DiagnosticBundleExportError.invalidSystemReport
        }
        guard (values.fileSize ?? 0) <= 20 * 1_024 * 1_024 else {
          throw DiagnosticBundleExportError.systemReportTooLarge
        }
        return url
      }
      guard selectedReports.count == preview.manifest.selectedSystemReports.count else {
        throw DiagnosticBundleExportError.invalidSystemReport
      }

      let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent(
        "current-diagnostics-\(UUID().uuidString)",
        isDirectory: true
      )
      let bundleDirectory = stagingRoot.appendingPathComponent(
        "GitCurrent Diagnostics",
        isDirectory: true
      )
      try fileManager.createDirectory(
        at: bundleDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      defer { try? fileManager.removeItem(at: stagingRoot) }

      for (name, data) in try preview.encodedFiles() {
        let fileURL = bundleDirectory.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: fileURL.path
        )
      }

      if !selectedReports.isEmpty {
        let reportsDirectory = bundleDirectory.appendingPathComponent(
          "system-reports",
          isDirectory: true
        )
        try fileManager.createDirectory(
          at: reportsDirectory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
        for (index, sourceURL) in selectedReports.enumerated() {
          let metadata = preview.manifest.selectedSystemReports[index]
          let destination = reportsDirectory.appendingPathComponent(
            metadata.archiveName
          )
          let didAccess = sourceURL.startAccessingSecurityScopedResource()
          defer {
            if didAccess {
              sourceURL.stopAccessingSecurityScopedResource()
            }
          }
          try fileManager.copyItem(at: sourceURL, to: destination)
          try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
          )
        }
      }

      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
      process.arguments = [
        "-c", "-k", "--norsrc", "--keepParent",
        bundleDirectory.path,
        destinationURL.path,
      ]
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw DiagnosticBundleExportError.archiveFailed(process.terminationStatus)
      }
    }.value
  }
}

public enum DiagnosticBundleFactory {
  public static func make(
    generatedAt: Date = Date(),
    appVersion: String,
    appBuild: String,
    operatingSystem: String,
    architecture: String,
    gitVersion: String?,
    gitLFSVersion: String?,
    gitSource: String,
    hasOpenRepository: Bool,
    loadedCommitCount: Int,
    workingCopyChangeCount: Int,
    activities: [OperationActivity],
    selectedSystemReports: [DiagnosticSystemReportMetadata]
  ) -> DiagnosticBundlePreview {
    let operations = activities.map { activity in
      let duration = activity.finishedAt.map {
        max(0, Int($0.timeIntervalSince(activity.startedAt) * 1_000))
      }
      return DiagnosticOperationRecord(
        startedAt: activity.startedAt,
        finishedAt: activity.finishedAt,
        state: activity.state,
        title: DiagnosticRedactor.operationCategory(for: activity.title),
        detail: nil,
        durationMilliseconds: duration
      )
    }
    let durations = operations.compactMap(\.durationMilliseconds)
    let performance = DiagnosticPerformanceSummary(
      operationCount: operations.count,
      runningCount: operations.count { $0.state == .running },
      succeededCount: operations.count { $0.state == .succeeded },
      failedCount: operations.count { $0.state == .failed },
      cancelledCount: operations.count { $0.state == .cancelled },
      averageDurationMilliseconds:
        durations.isEmpty ? nil : durations.reduce(0, +) / durations.count,
      maximumDurationMilliseconds: durations.max()
    )
    return DiagnosticBundlePreview(
      manifest: DiagnosticBundleManifest(
        generatedAt: generatedAt,
        appVersion: appVersion,
        appBuild: appBuild,
        operatingSystem: operatingSystem,
        architecture: architecture,
        gitVersion: gitVersion,
        gitLFSVersion: gitLFSVersion,
        gitSource: gitSource,
        hasOpenRepository: hasOpenRepository,
        loadedCommitCount: loadedCommitCount,
        workingCopyChangeCount: workingCopyChangeCount,
        selectedSystemReports: selectedSystemReports,
        performance: performance
      ),
      operations: operations
    )
  }
}

public enum DiagnosticRedactor {
  public static func operationCategory(for title: String) -> String {
    let normalized = title.lowercased()
    let categories: [(terms: [String], category: String)] = [
      (["git lfs"], "Git LFS"),
      (["submodule"], "Submodule"),
      (["worktree"], "Worktree"),
      (["external merge"], "External merge"),
      (["external diff"], "External diff"),
      (["unstage"], "Unstage"),
      (["stage"], "Stage"),
      (["cherry-pick"], "Cherry-pick"),
      (["revert"], "Revert"),
      (["reset"], "Reset"),
      (["rebase"], "Rebase"),
      (["merge"], "Merge"),
      (["check out", "checkout"], "Checkout"),
      (["commit"], "Commit"),
      (["stash", "apply stash", "pop stash", "drop stash"], "Stash"),
      (["tag"], "Tag"),
      (["remote"], "Remote"),
      (["fetch"], "Fetch"),
      (["pull"], "Pull"),
      (["push"], "Push"),
      (["clone"], "Clone"),
      (["initialize"], "Initialize"),
      (["maintenance"], "Maintenance"),
      (["resolve"], "Conflict resolution"),
      (["undo"], "Undo"),
    ]
    return categories.first { entry in
      entry.terms.contains { normalized.contains($0) }
    }?.category ?? "Git operation"
  }

  public static func redact(_ input: String) -> String {
    var output = input
    output = replacing(
      #"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----"#,
      in: output,
      with: "<redacted-private-key>",
      options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    output = replacing(
      #"(?i)\bauthorization\s*[:=]\s*[^\r\n]+"#,
      in: output,
      with: "Authorization=<redacted>"
    )
    output = replacing(
      #"(?i)\bBearer\s+[A-Za-z0-9._~+/\-=]+"#,
      in: output,
      with: "Bearer <redacted>"
    )
    output = replacing(
      #"(?i)\b(token|access[_-]?token|password|passwd|secret|api[_-]?key|credential)\s*[:=]\s*[^\s,;]+"#,
      in: output,
      withTemplate: "$1=<redacted>"
    )
    output = redactURLs(in: output)
    output = replacing(
      #"\b[\w.-]+@[\w.-]+:[^\s'"]+"#,
      in: output,
      with: "<redacted-remote>"
    )
    output = replacing(
      #"/(?:Users|home)/[^\r\n]*"#,
      in: output,
      with: "<path>"
    )
    return output
  }

  private static func redactURLs(in input: String) -> String {
    guard
      let expression = try? NSRegularExpression(
        pattern: #"\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s'"]+"#
      )
    else {
      return input
    }
    var output = input
    let matches = expression.matches(
      in: input,
      range: NSRange(input.startIndex..., in: input)
    )
    for match in matches.reversed() {
      guard
        let range = Range(match.range, in: input),
        let outputRange = Range(match.range, in: output)
      else {
        continue
      }
      let value = String(input[range])
      guard let components = URLComponents(string: value) else {
        output.replaceSubrange(outputRange, with: "<redacted-url>")
        continue
      }
      guard let scheme = components.scheme, let host = components.host else {
        output.replaceSubrange(outputRange, with: "<redacted-url>")
        continue
      }
      var redacted = "\(scheme)://\(host)"
      if let port = components.port {
        redacted += ":\(port)"
      }
      if !components.path.isEmpty {
        redacted += "/<redacted-path>"
      }
      output.replaceSubrange(
        outputRange,
        with: redacted
      )
    }
    return output
  }

  private static func replacing(
    _ pattern: String,
    in input: String,
    with replacement: String,
    options: NSRegularExpression.Options = []
  ) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options)
    else {
      return input
    }
    return expression.stringByReplacingMatches(
      in: input,
      range: NSRange(input.startIndex..., in: input),
      withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
    )
  }

  private static func replacing(
    _ pattern: String,
    in input: String,
    withTemplate replacement: String
  ) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return input
    }
    return expression.stringByReplacingMatches(
      in: input,
      range: NSRange(input.startIndex..., in: input),
      withTemplate: replacement
    )
  }
}
