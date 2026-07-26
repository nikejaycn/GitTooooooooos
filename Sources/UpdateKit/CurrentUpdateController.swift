import Foundation
import Sparkle

public struct UpdateConfiguration: Equatable, Sendable {
  public let feedURL: URL?
  public let publicEdKey: String?

  public init(infoDictionary: [String: Any]?) {
    let rawFeed = infoDictionary?["SUFeedURL"] as? String
    let candidateFeed = rawFeed.flatMap(URL.init(string:))
    if let candidateFeed, candidateFeed.scheme?.lowercased() == "https" {
      feedURL = candidateFeed
    } else {
      feedURL = nil
    }
    let key = (infoDictionary?["SUPublicEDKey"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    publicEdKey = key?.isEmpty == false ? key : nil
  }

  public var isReadyForSignedUpdates: Bool {
    feedURL != nil && publicEdKey != nil
  }
}

@MainActor
public final class CurrentUpdateController {
  public let configuration: UpdateConfiguration
  private let controller: SPUStandardUpdaterController

  public init(bundle: Bundle = .main) {
    configuration = UpdateConfiguration(infoDictionary: bundle.infoDictionary)
    controller = SPUStandardUpdaterController(
      startingUpdater: configuration.isReadyForSignedUpdates,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  public var canCheckForUpdates: Bool {
    configuration.isReadyForSignedUpdates && controller.updater.canCheckForUpdates
  }

  public var automaticallyChecksForUpdates: Bool {
    get {
      configuration.isReadyForSignedUpdates
        && controller.updater.automaticallyChecksForUpdates
    }
    set {
      guard configuration.isReadyForSignedUpdates else { return }
      controller.updater.automaticallyChecksForUpdates = newValue
    }
  }

  public var statusDescription: String {
    guard configuration.feedURL != nil else {
      return "Update feed will be configured during release engineering."
    }
    guard configuration.publicEdKey != nil else {
      return "Sparkle EdDSA public key will be configured during release engineering."
    }
    return "Signed Sparkle updates are configured."
  }

  public func checkForUpdates() {
    guard canCheckForUpdates else { return }
    controller.checkForUpdates(nil)
  }
}
