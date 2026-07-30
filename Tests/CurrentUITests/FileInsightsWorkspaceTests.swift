import CurrentDomain
import Foundation
import Testing

@testable import CurrentUI

@Suite("File insights workspace")
struct FileInsightsWorkspaceTests {
  @Test("Blame help keeps attribution and rename provenance together")
  @MainActor
  func blameHelp() {
    let line = BlameLine(
      oid: "1234567890abcdef",
      originalLineNumber: 7,
      finalLineNumber: 9,
      authorName: "Joe",
      authorEmail: "joe@example.com",
      authoredAt: Date(timeIntervalSince1970: 0),
      summary: "Rename file",
      originalPath: GitPath("Sources/New.swift"),
      previousOID: "fedcba0987654321",
      previousPath: GitPath("Sources/Old.swift"),
      content: "let value = true"
    )

    let help = FileInsightsWorkspace.blameHelp(line)
    #expect(help.contains("Joe <joe@example.com>"))
    #expect(help.contains("Original: Sources/New.swift:7"))
    #expect(help.contains("Previous: fedcba0987654321 Sources/Old.swift"))
  }
}
