import CurrentAppSupport
import CurrentDomain
import Foundation
import Testing

@Suite("External tool service")
@MainActor
struct ExternalToolServiceTests {
  @Test("A configured executable resolves without exposing process details")
  func resolvesCustomExecutable() throws {
    let service = ExternalToolService()
    let executable = try service.resolveExecutable(
      .custom,
      customPath: "/usr/bin/true",
      role: "diff"
    )

    #expect(executable.path == "/usr/bin/true")
  }

  @Test("Missing configuration and invalid custom tools have distinct errors")
  func reportsConfigurationErrors() {
    let service = ExternalToolService()

    do {
      _ = try service.resolveExecutable(.none, customPath: "", role: "merge")
      Issue.record("Expected an unconfigured-tool error")
    } catch {
      #expect(error as? ExternalToolServiceError == .notConfigured("merge"))
    }

    do {
      _ = try service.resolveExecutable(
        .custom,
        customPath: "/path/that/does/not/exist",
        role: "diff"
      )
      Issue.record("Expected a missing-tool error")
    } catch let error as ExternalToolServiceError {
      guard case .notFound = error else {
        Issue.record("Expected a not-found error")
        return
      }
    } catch {
      Issue.record("Expected ExternalToolServiceError")
    }
  }
}
