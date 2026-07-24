import CurrentDomain
import Foundation
import Testing

@Suite("Manual diagnostic bundle")
struct DiagnosticsTests {
  @Test("Redacts credentials, repository URLs, home paths, and private keys")
  func redaction() {
    let input = """
      Authorization: Bearer abc.def
      token=super-secret
      https://alice:password@example.com/private/repository.git?access_token=hidden
      /Users/alice/Secret Repository/file.swift
      git@example.com:private/repository.git
      -----BEGIN OPENSSH PRIVATE KEY-----
      private-material
      -----END OPENSSH PRIVATE KEY-----
      """
    let redacted = DiagnosticRedactor.redact(input)

    #expect(!redacted.contains("abc.def"))
    #expect(!redacted.contains("super-secret"))
    #expect(!redacted.contains("alice"))
    #expect(!redacted.contains("private-material"))
    #expect(!redacted.contains("private/repository"))
    #expect(redacted.contains("https://example.com/<redacted-path>"))
    #expect(redacted.contains("<path>"))
    #expect(redacted.contains("<redacted-remote>"))
    #expect(redacted.contains("<redacted-private-key>"))
  }

  @Test("Builds a bounded preview without automatic collection or upload")
  func preview() throws {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let preview = DiagnosticBundleFactory.make(
      generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
      appVersion: "1.0",
      appBuild: "42",
      operatingSystem: "macOS",
      architecture: "arm64",
      gitVersion: "git version 2.50.0",
      gitLFSVersion: nil,
      gitSource: "bundled",
      hasOpenRepository: true,
      loadedCommitCount: 200,
      workingCopyChangeCount: 3,
      activities: [
        OperationActivity(
          title: "Fetch https://me:secret@example.com/team/repository.git",
          startedAt: startedAt,
          finishedAt: startedAt.addingTimeInterval(1.25),
          state: .failed,
          detail: "token=never-export"
        )
      ],
      selectedSystemReports: [
        DiagnosticSystemReportMetadata(
          archiveName: "system-report-1.ips",
          byteCount: 512
        )
      ]
    )
    let files = try preview.encodedFiles()
    let rendered = preview.renderedPreview()

    #expect(Set(files.keys) == ["manifest.json", "operations.json"])
    #expect(preview.manifest.automaticCollectionEnabled == false)
    #expect(preview.manifest.automaticUploadEnabled == false)
    #expect(preview.manifest.performance.failedCount == 1)
    #expect(preview.manifest.performance.averageDurationMilliseconds == 1_250)
    #expect(preview.operations.first?.title == "Fetch")
    #expect(preview.operations.first?.detail == nil)
    #expect(!rendered.contains("secret"))
    #expect(!rendered.contains("never-export"))
    #expect(!rendered.contains("team/repository"))
    #expect(rendered.contains("system-report-1.ips"))
  }

  @Test("Exports an inspectable ZIP with neutral system report names")
  func archiveExport() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "current-diagnostic-test-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let selectedReport = root.appendingPathComponent(
      "Alice Private Crash Report.ips"
    )
    try Data("selected report body".utf8).write(to: selectedReport)
    let archive = root.appendingPathComponent("diagnostics.zip")
    let preview = DiagnosticBundleFactory.make(
      generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
      appVersion: "1.0",
      appBuild: "42",
      operatingSystem: "macOS",
      architecture: "arm64",
      gitVersion: "git version 2.50.0",
      gitLFSVersion: nil,
      gitSource: "bundled",
      hasOpenRepository: false,
      loadedCommitCount: 0,
      workingCopyChangeCount: 0,
      activities: [],
      selectedSystemReports: [
        DiagnosticSystemReportMetadata(
          archiveName: "system-report-1.ips",
          byteCount: 20
        )
      ]
    )

    try await DiagnosticBundleExporter.export(
      preview: preview,
      selectedSystemReportURLs: [selectedReport],
      to: archive
    )
    #expect(fileManager.fileExists(atPath: archive.path))

    let extracted = root.appendingPathComponent("extracted", isDirectory: true)
    try fileManager.createDirectory(at: extracted, withIntermediateDirectories: false)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path, extracted.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let bundle = extracted.appendingPathComponent(
      "Current Diagnostics",
      isDirectory: true
    )
    let manifest = bundle.appendingPathComponent("manifest.json")
    let operations = bundle.appendingPathComponent("operations.json")
    let copiedReport = bundle.appendingPathComponent(
      "system-reports/system-report-1.ips"
    )
    #expect(fileManager.fileExists(atPath: manifest.path))
    #expect(fileManager.fileExists(atPath: operations.path))
    #expect(try Data(contentsOf: copiedReport) == Data("selected report body".utf8))

    let archivedPaths = try #require(
      fileManager.enumerator(at: bundle, includingPropertiesForKeys: nil)?
        .allObjects as? [URL]
    )
    #expect(!archivedPaths.map(\.lastPathComponent).contains(selectedReport.lastPathComponent))
    let manifestText = try String(contentsOf: manifest, encoding: .utf8)
    #expect(!manifestText.contains("Alice"))
    #expect(manifestText.contains("system-report-1.ips"))
  }
}
