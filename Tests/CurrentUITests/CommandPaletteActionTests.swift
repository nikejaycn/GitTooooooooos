import Testing

@testable import CurrentUI

@Suite("Command palette action search")
struct CommandPaletteActionTests {
  private let action = CommandPaletteAction(
    id: "branch.topic",
    title: "Check Out topic",
    detail: "origin/topic",
    systemImage: "arrow.triangle.branch",
    keywords: "branch switch checkout refs/heads/topic"
  ) {}

  @Test("Matches title, detail, keywords, and unordered terms")
  func matchesIndexedFields() {
    #expect(action.matches("check topic"))
    #expect(action.matches("origin"))
    #expect(action.matches("refs/heads"))
    #expect(action.matches("topic branch"))
  }

  @Test("Uses AND semantics and ignores case and surrounding whitespace")
  func querySemantics() {
    #expect(action.matches("  TOPIC   CHECKOUT "))
    #expect(!action.matches("topic missing"))
    #expect(action.matches(""))
  }
}
