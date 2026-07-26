import Foundation
import Testing
import UpdateKit

@Suite("Signed Sparkle update configuration")
struct UpdateConfigurationTests {
  @Test("Requires an HTTPS feed and non-empty EdDSA public key")
  func signedConfiguration() {
    let ready = UpdateConfiguration(
      infoDictionary: [
        "SUFeedURL": "https://updates.example.test/current/appcast.xml",
        "SUPublicEDKey": "public-key",
      ]
    )
    #expect(ready.isReadyForSignedUpdates)

    #expect(
      !UpdateConfiguration(
        infoDictionary: [
          "SUFeedURL": "http://updates.example.test/appcast.xml",
          "SUPublicEDKey": "public-key",
        ]
      ).isReadyForSignedUpdates
    )
    #expect(
      !UpdateConfiguration(
        infoDictionary: [
          "SUFeedURL": "https://updates.example.test/appcast.xml",
          "SUPublicEDKey": " ",
        ]
      ).isReadyForSignedUpdates
    )
  }
}
