import CurrentDomain
import CurrentUI
import DiffKit
import Foundation
import GraphKit

/// Owns the persistence format for user-level application preferences.
///
/// `AppModel` coordinates behavior; this store is the single place that knows UserDefaults
/// keys, serialization details, and compatibility defaults.
public struct AppPreferencesStore {
  private enum Key {
    static let recentRepositories = "Current.recentRepositories.v1"
    static let maximumLoadedCommitCount = "Current.maximumLoadedCommitCount.v1"
    static let useCustomGit = "Current.useCustomGit.v1"
    static let customGitPath = "Current.customGitPath.v1"
    static let appearance = "Current.appearance.v1"
    static let autoStashEnabled = "Current.autoStashEnabled.v1"
    static let externalDiffTool = "Current.externalDiffTool.v1"
    static let externalMergeTool = "Current.externalMergeTool.v1"
    static let customDiffToolPath = "Current.customDiffToolPath.v1"
    static let customMergeToolPath = "Current.customMergeToolPath.v1"
    static let graphColumns = "Current.graphColumns.v1"
    static let graphDensity = "Current.graphDensity.v1"
    static let graphScale = "Current.graphScale.v1"
    static let ignoresWhitespaceChanges = "Current.ignoresWhitespaceChanges.v1"
    static let ignoresEndOfLineWhitespace = "Current.ignoresEndOfLineWhitespace.v1"
    static let diffTextFontName = "Current.diffTextFontName.v1"
    static let diffTextFontSize = "Current.diffTextFontSize.v1"
    static let hiddenGraphReferences = "Current.hiddenGraphReferences.v1"
    static let soloGraphReference = "Current.soloGraphReference.v1"
    static let pinnedGraphReferences = "Current.pinnedGraphReferences.v1"
    static let visibleSidebarSections = "Current.visibleSidebarSections.v1"
  }

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var recentRepositories: [RecentRepository] {
    get {
      guard
        let data = defaults.data(forKey: Key.recentRepositories),
        let repositories = try? JSONDecoder().decode([RecentRepository].self, from: data)
      else {
        return []
      }
      return Array(repositories.prefix(100))
    }
    nonmutating set {
      guard let data = try? JSONEncoder().encode(Array(newValue.prefix(100))) else { return }
      defaults.set(data, forKey: Key.recentRepositories)
    }
  }

  public var maximumLoadedCommitCount: Int {
    get { defaults.integer(forKey: Key.maximumLoadedCommitCount) }
    nonmutating set { defaults.set(newValue, forKey: Key.maximumLoadedCommitCount) }
  }

  public var useCustomGit: Bool {
    get { defaults.bool(forKey: Key.useCustomGit) }
    nonmutating set { defaults.set(newValue, forKey: Key.useCustomGit) }
  }

  public var customGitPath: String {
    get { defaults.string(forKey: Key.customGitPath) ?? "" }
    nonmutating set { defaults.set(newValue, forKey: Key.customGitPath) }
  }

  public var appearance: AppAppearance {
    get {
      defaults.string(forKey: Key.appearance)
        .flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
  }

  public var autoStashEnabled: Bool {
    get { defaults.bool(forKey: Key.autoStashEnabled) }
    nonmutating set { defaults.set(newValue, forKey: Key.autoStashEnabled) }
  }

  public var externalDiffTool: ExternalTool {
    get {
      defaults.string(forKey: Key.externalDiffTool)
        .flatMap(ExternalTool.init(rawValue:)) ?? .none
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Key.externalDiffTool) }
  }

  public var externalMergeTool: ExternalTool {
    get {
      defaults.string(forKey: Key.externalMergeTool)
        .flatMap(ExternalTool.init(rawValue:)) ?? .none
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Key.externalMergeTool) }
  }

  public var customDiffToolPath: String {
    get { defaults.string(forKey: Key.customDiffToolPath) ?? "" }
    nonmutating set { defaults.set(newValue, forKey: Key.customDiffToolPath) }
  }

  public var customMergeToolPath: String {
    get { defaults.string(forKey: Key.customMergeToolPath) ?? "" }
    nonmutating set { defaults.set(newValue, forKey: Key.customMergeToolPath) }
  }

  public var graphDisplayConfiguration: GraphDisplayConfiguration {
    get {
      let columns =
        defaults.stringArray(forKey: Key.graphColumns).map {
          Set($0.compactMap(GraphOptionalColumn.init(rawValue:)))
        } ?? Set(GraphOptionalColumn.allCases)
      let density =
        defaults.string(forKey: Key.graphDensity)
        .flatMap(GraphRowDensity.init(rawValue:)) ?? .comfortable
      let savedScale = defaults.double(forKey: Key.graphScale)
      return GraphDisplayConfiguration(
        visibleOptionalColumns: columns,
        density: density,
        scale: savedScale == 0 ? 1 : savedScale
      )
    }
    nonmutating set {
      defaults.set(
        GraphOptionalColumn.allCases
          .filter(newValue.visibleOptionalColumns.contains)
          .map(\.rawValue),
        forKey: Key.graphColumns
      )
      defaults.set(newValue.density.rawValue, forKey: Key.graphDensity)
      defaults.set(newValue.scale, forKey: Key.graphScale)
    }
  }

  public var diffOptions: DiffOptions {
    get {
      DiffOptions(
        ignoresWhitespaceChanges: defaults.bool(forKey: Key.ignoresWhitespaceChanges),
        ignoresEndOfLineWhitespace: defaults.bool(
          forKey: Key.ignoresEndOfLineWhitespace
        )
      )
    }
    nonmutating set {
      defaults.set(
        newValue.ignoresWhitespaceChanges,
        forKey: Key.ignoresWhitespaceChanges
      )
      defaults.set(
        newValue.ignoresEndOfLineWhitespace,
        forKey: Key.ignoresEndOfLineWhitespace
      )
    }
  }

  public var diffTextConfiguration: DiffTextConfiguration {
    get {
      let savedSize = defaults.double(forKey: Key.diffTextFontSize)
      return DiffTextConfiguration(
        fontName: defaults.string(forKey: Key.diffTextFontName),
        fontSize: savedSize == 0 ? 12 : savedSize
      )
    }
    nonmutating set {
      if let fontName = newValue.fontName {
        defaults.set(fontName, forKey: Key.diffTextFontName)
      } else {
        defaults.removeObject(forKey: Key.diffTextFontName)
      }
      defaults.set(newValue.fontSize, forKey: Key.diffTextFontSize)
    }
  }

  public var hiddenGraphReferences: Set<String> {
    get { Set(defaults.stringArray(forKey: Key.hiddenGraphReferences) ?? []) }
    nonmutating set { defaults.set(newValue.sorted(), forKey: Key.hiddenGraphReferences) }
  }

  public var soloGraphReference: String? {
    get { defaults.string(forKey: Key.soloGraphReference) }
    nonmutating set {
      if let newValue {
        defaults.set(newValue, forKey: Key.soloGraphReference)
      } else {
        defaults.removeObject(forKey: Key.soloGraphReference)
      }
    }
  }

  public var pinnedGraphReferences: Set<String> {
    get { Set(defaults.stringArray(forKey: Key.pinnedGraphReferences) ?? []) }
    nonmutating set { defaults.set(newValue.sorted(), forKey: Key.pinnedGraphReferences) }
  }

  public var visibleSidebarSections: Set<SidebarSection> {
    get {
      SidebarSection.visibleSections(
        from: defaults.stringArray(forKey: Key.visibleSidebarSections)
      )
    }
    nonmutating set {
      defaults.set(
        SidebarSection.allCases.filter(newValue.contains).map(\.rawValue),
        forKey: Key.visibleSidebarSections
      )
    }
  }
}
