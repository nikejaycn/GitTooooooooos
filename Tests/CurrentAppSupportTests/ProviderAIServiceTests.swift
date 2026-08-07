import CurrentAppSupport
import CurrentDomain
import Foundation
import Testing

@Suite("AI provider HTTP clients")
struct ProviderAIServiceTests {
  @Test("DeepSeek uses its official endpoint and bearer authentication")
  func deepSeekCommitMessage() async throws {
    let transport = RecordingAITransport(
      response: #"{"choices":[{"message":{"content":"{\"subject\":\"feat: add search\",\"body\":\"Keep results local.\"}"}}]}"#
    )
    let service = ProviderAIService(
      keyStore: TestAIKeyStore(key: "deepseek-secret"),
      transport: transport
    )
    let configuration = AIConfiguration(
      provider: .deepSeek,
      model: "deepseek-v4-flash",
      baseURL: "https://ignored.example"
    )

    let message = try await service.generateCommitMessage(
      repositoryName: "Current",
      context: "diff --git a/A.swift b/A.swift",
      configuration: configuration
    )
    let request = try #require(await transport.lastRequest)

    #expect(message == "feat: add search\n\nKeep results local.")
    #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-secret")
    let body = try #require(request.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["model"] as? String == "deepseek-v4-flash")
  }

  @Test("OpenAI Responses API structured output is decoded")
  func openAICommitMessage() async throws {
    let transport = RecordingAITransport(
      response: #"{"output":[{"content":[{"type":"output_text","text":"{\"subject\":\"fix: handle empty refs\",\"body\":\"\"}"}]}]}"#
    )
    let service = ProviderAIService(
      keyStore: TestAIKeyStore(key: "openai-secret"),
      transport: transport
    )
    let configuration = AIConfiguration(
      provider: .openAI,
      model: "gpt-5.6-sol",
      baseURL: ""
    )

    let message = try await service.generateCommitMessage(
      repositoryName: "Current",
      context: "diff",
      configuration: configuration
    )
    let request = try #require(await transport.lastRequest)

    #expect(message == "fix: handle empty refs")
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-secret")
  }

  @Test("Anthropic and Gemini use provider-specific API key headers")
  func providerSpecificHeaders() async throws {
    let anthropicTransport = RecordingAITransport(
      response: #"{"content":[{"type":"text","text":"{\"subject\":\"docs: explain setup\",\"body\":\"\"}"}]}"#
    )
    let anthropic = ProviderAIService(
      keyStore: TestAIKeyStore(key: "anthropic-secret"),
      transport: anthropicTransport
    )
    _ = try await anthropic.generateCommitMessage(
      repositoryName: "Current",
      context: "diff",
      configuration: AIConfiguration(
        provider: .anthropic,
        model: "claude-sonnet-5",
        baseURL: ""
      )
    )
    let anthropicRequest = try #require(await anthropicTransport.lastRequest)
    #expect(anthropicRequest.value(forHTTPHeaderField: "x-api-key") == "anthropic-secret")
    #expect(
      anthropicRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01"
    )

    let geminiTransport = RecordingAITransport(
      response: #"{"candidates":[{"content":{"parts":[{"text":"{\"subject\":\"test: cover providers\",\"body\":\"\"}"}]}}]}"#
    )
    let gemini = ProviderAIService(
      keyStore: TestAIKeyStore(key: "gemini-secret"),
      transport: geminiTransport
    )
    _ = try await gemini.generateCommitMessage(
      repositoryName: "Current",
      context: "diff",
      configuration: AIConfiguration(
        provider: .googleGemini,
        model: "gemini-3.6-flash",
        baseURL: ""
      )
    )
    let geminiRequest = try #require(await geminiTransport.lastRequest)
    #expect(geminiRequest.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-secret")
    #expect(
      geminiRequest.url?.absoluteString
        == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"
    )
  }

  @Test("Commit composition validates and maps provider change IDs")
  func composition() async throws {
    let transport = RecordingAITransport(
      response: #"{"choices":[{"message":{"content":"{\"groups\":[{\"message\":\"feat: add A\",\"change_ids\":[\"change-1\"]},{\"message\":\"test: cover B\",\"change_ids\":[\"change-2\"]}]}"}}]}"#
    )
    let service = ProviderAIService(
      keyStore: TestAIKeyStore(key: "secret"),
      transport: transport
    )
    let units = [unit("change-1", path: "A.swift"), unit("change-2", path: "B.swift")]

    let groups = try await service.composeCommits(
      repositoryName: "Current",
      units: units,
      configuration: AIConfiguration(
        provider: .deepSeek,
        model: "deepseek-v4-flash",
        baseURL: ""
      )
    )

    #expect(groups.map(\.unitIDs) == [["change-1"], ["change-2"]])
  }

  @Test("Missing keys and insecure remote custom endpoints are unavailable")
  func invalidConfiguration() {
    let missingKeyService = ProviderAIService(
      keyStore: TestAIKeyStore(key: nil),
      transport: RecordingAITransport(response: "{}")
    )
    let missingKey = missingKeyService.availability(
      for: AIConfiguration(provider: .deepSeek, model: "deepseek-v4-flash", baseURL: "")
    )
    #expect(missingKey.isAvailable == false)

    let insecureService = ProviderAIService(
      keyStore: TestAIKeyStore(key: "secret"),
      transport: RecordingAITransport(response: "{}")
    )
    let insecure = insecureService.availability(
      for: AIConfiguration(
        provider: .openAICompatible,
        model: "model",
        baseURL: "http://api.example.com/v1"
      )
    )
    #expect(insecure.statusText == "Remote AI endpoints must use HTTPS")
  }

  private func unit(_ id: String, path: String) -> CommitCompositionUnit {
    CommitCompositionUnit(
      id: id,
      path: GitPath(path),
      summary: "Modified",
      patchText: nil,
      analysisText: "+ change"
    )
  }
}

private struct TestAIKeyStore: AIAPIKeyStore {
  let key: String?

  func containsAPIKey(for provider: AIProvider) throws -> Bool { key?.isEmpty == false }
  func apiKey(for provider: AIProvider) throws -> String? { key }
  func setAPIKey(_ apiKey: String, for provider: AIProvider) throws {}
  func removeAPIKey(for provider: AIProvider) throws {}
}

private actor RecordingAITransport: AIHTTPTransport {
  private let response: Data
  private let statusCode: Int
  private(set) var lastRequest: URLRequest?

  init(response: String, statusCode: Int = 200) {
    self.response = Data(response.utf8)
    self.statusCode = statusCode
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lastRequest = request
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://example.com")!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    return (self.response, response)
  }
}
