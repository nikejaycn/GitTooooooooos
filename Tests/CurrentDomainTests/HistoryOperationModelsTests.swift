import CurrentDomain
import Testing

@Suite("History rewrite presets")
struct HistoryOperationModelsTests {
  @Test("Squash marks the older selected commit as the retained pick")
  func squashSelectedCommits() throws {
    let plan = plan()

    let rewritten = try plan.applying(.squash, to: [oid("c"), oid("b")])

    #expect(rewritten.steps.map(\.action) == [.pick, .pick, .squash, .pick])
  }

  @Test("Drop can remove a non-contiguous set of commits")
  func dropSelectedCommits() throws {
    let plan = plan()

    let rewritten = try plan.applying(.drop, to: [oid("d"), oid("b")])

    #expect(rewritten.steps.map(\.action) == [.pick, .drop, .pick, .drop])
  }

  @Test("Move down keeps the selected block together and moves it toward the base")
  func moveSelectedCommitsDown() throws {
    let plan = plan()

    let rewritten = try plan.applying(.moveDown, to: [oid("c"), oid("b")])

    #expect(rewritten.steps.map(\.oid) == [oid("b"), oid("c"), oid("a"), oid("d")])
  }

  @Test("Squash and move down reject a non-contiguous selection")
  func contiguousActionsRejectGaps() throws {
    let plan = plan()

    #expect(throws: HistoryRewriteError.selectionMustBeContiguous) {
      try plan.applying(.squash, to: [oid("d"), oid("b")])
    }
    #expect(throws: HistoryRewriteError.selectionMustBeContiguous) {
      try plan.applying(.moveDown, to: [oid("d"), oid("b")])
    }
  }

  @Test("Move down rejects a block already at the base")
  func moveBaseBlockDown() throws {
    #expect(throws: HistoryRewriteError.cannotMoveDown) {
      try plan().applying(.moveDown, to: [oid("b"), oid("a")])
    }
  }

  private func plan() -> InteractiveRebasePlan {
    InteractiveRebasePlan(
      upstreamOID: oid("base"),
      originalHeadOID: oid("d"),
      steps: [
        InteractiveRebaseStep(oid: oid("a"), subject: "A"),
        InteractiveRebaseStep(oid: oid("b"), subject: "B"),
        InteractiveRebaseStep(oid: oid("c"), subject: "C"),
        InteractiveRebaseStep(oid: oid("d"), subject: "D"),
      ]
    )
  }

  private func oid(_ suffix: String) -> String {
    String(repeating: suffix, count: 40)
  }
}
