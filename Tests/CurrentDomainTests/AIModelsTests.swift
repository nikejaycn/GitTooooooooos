import CurrentDomain
import Testing

@Suite("AI commit composition models")
struct AIModelsTests {
  @Test("AI providers expose safe provider-specific defaults")
  func providerDefaults() {
    #expect(AIProvider.deepSeek.defaultModel == "deepseek-v4-flash")
    #expect(AIProvider.deepSeek.defaultBaseURL == "https://api.deepseek.com")
    #expect(AIProvider.appleIntelligence.requiresAPIKey == false)
    #expect(AIProvider.openAI.requiresAPIKey)
    #expect(AIConfiguration().provider == .appleIntelligence)
  }

  @Test("A valid composition assigns every change exactly once")
  func validComposition() {
    let units = [unit("a"), unit("b")]
    let plan = CommitCompositionPlan(
      units: units,
      groups: [
        CommitCompositionGroup(message: "Add A", unitIDs: ["a"]),
        CommitCompositionGroup(message: "Add B", unitIDs: ["b"]),
      ]
    )

    #expect(plan.validationMessage == nil)
  }

  @Test("Composition rejects missing, duplicate, empty, and unknown assignments")
  func invalidComposition() {
    let units = [unit("a"), unit("b")]

    #expect(
      CommitCompositionPlan(
        units: units,
        groups: [CommitCompositionGroup(message: "Only A", unitIDs: ["a"])]
      ).validationMessage == "Assign every change to a commit."
    )
    #expect(
      CommitCompositionPlan(
        units: units,
        groups: [CommitCompositionGroup(message: "Duplicate", unitIDs: ["a", "a"])]
      ).validationMessage == "A change can only belong to one commit."
    )
    #expect(
      CommitCompositionPlan(
        units: units,
        groups: [
          CommitCompositionGroup(message: "", unitIDs: ["a"]),
          CommitCompositionGroup(message: "B", unitIDs: ["b"]),
        ]
      ).validationMessage == "Enter a message for every commit."
    )
    #expect(
      CommitCompositionPlan(
        units: units,
        groups: [CommitCompositionGroup(message: "Unknown", unitIDs: ["a", "c"])]
      ).validationMessage == "The composition contains an unknown change."
    )
  }

  private func unit(_ id: String) -> CommitCompositionUnit {
    CommitCompositionUnit(
      id: id,
      path: GitPath("\(id).swift"),
      summary: "Change \(id)",
      patchText: nil,
      analysisText: ""
    )
  }
}
