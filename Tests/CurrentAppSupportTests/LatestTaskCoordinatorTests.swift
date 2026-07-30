import CurrentAppSupport
import Foundation
import Testing

@MainActor
@Suite("Latest task coordinator")
struct LatestTaskCoordinatorTests {
  @Test("Starting new work invalidates and cancels the previous request")
  func replacesPreviousRequest() async {
    let coordinator = LatestTaskCoordinator()
    let first = coordinator.start { _ in
      try? await Task.sleep(for: .seconds(30))
    }
    let second = coordinator.start { _ in
      try? await Task.sleep(for: .seconds(30))
    }

    #expect(!coordinator.isCurrent(first))
    #expect(coordinator.isCurrent(second))

    coordinator.cancel()
    #expect(!coordinator.isRunning)
    #expect(!coordinator.isCurrent(second))
  }

  @Test("Completed work clears its identity")
  func completesCurrentRequest() async {
    let coordinator = LatestTaskCoordinator()
    let request = coordinator.start { _ in }

    for _ in 0..<10 where coordinator.isRunning {
      await Task.yield()
    }

    #expect(!coordinator.isRunning)
    #expect(!coordinator.isCurrent(request))
  }
}
