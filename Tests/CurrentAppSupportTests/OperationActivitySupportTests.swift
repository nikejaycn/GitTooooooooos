import CurrentAppSupport
import CurrentDomain
import Testing

@Suite("Operation activity support")
struct OperationActivitySupportTests {
  @Test("The operation log is newest-first, bounded, and finishable")
  func boundedActivityLog() throws {
    var log = OperationActivityLog(limit: 2)
    let first = log.begin("First")
    let second = log.begin("Second")
    let third = log.begin("Third")

    #expect(log.activities.map(\.title) == ["Third", "Second"])
    #expect(!log.activities.contains { $0.id == first })

    log.finish(second, state: .failed, detail: "Stopped")
    let finished = try #require(log.activities.first { $0.id == second })
    #expect(finished.state == .failed)
    #expect(finished.detail == "Stopped")
    #expect(finished.finishedAt != nil)

    log.finish(third, state: .succeeded)
    #expect(log.activities.first?.state == .succeeded)
  }

  @Test("Mutation titles are owned by one cross-domain catalog")
  func mutationTitles() {
    let path = GitPath("folder/file.txt")

    #expect(
      OperationActivityTitle.title(
        for: BranchMutation.checkoutRemote(
          remoteBranch: "origin/topic",
          localName: "topic",
          autoStash: false
        )
      ) == "Check out origin/topic as topic"
    )
    #expect(
      OperationActivityTitle.title(
        for: StashMutation.save(
          message: nil,
          includeUntracked: false,
          paths: [path]
        )
      ) == "Stash 1 selected path"
    )
    #expect(
      OperationActivityTitle.title(
        for: RemoteMutation.push(
          remote: "origin",
          branch: "main",
          setUpstream: false,
          forceWithLease: true
        )
      ) == "Force-with-lease push main to origin"
    )
    #expect(
      OperationActivityTitle.title(
        for: HistoryMutation.reset(
          target: "1234567890abcdef",
          mode: .hard
        )
      ) == "Hard reset to 1234567890ab"
    )
  }
}
