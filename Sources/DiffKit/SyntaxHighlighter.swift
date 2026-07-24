import CurrentDomain
import Foundation
import SwiftTreeSitter
import TreeSitterC
import TreeSitterCPP
import TreeSitterGo
import TreeSitterJSON
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterObjc
import TreeSitterPython
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

public enum SyntaxLanguage: String, CaseIterable, Hashable, Sendable {
  case swift
  case c
  case cpp
  case objectiveC
  case javaScript
  case typeScript
  case tsx
  case python
  case go
  case rust
  case java
  case json
  case yaml

  public static func detect(path: GitPath) -> SyntaxLanguage? {
    guard
      let path = String(bytes: path.rawBytes, encoding: .utf8),
      let fileExtension = path.split(separator: ".").last?.lowercased()
    else {
      return nil
    }
    return switch fileExtension {
    case "swift": .swift
    case "c", "h": .c
    case "cc", "cpp", "cxx", "hh", "hpp", "hxx": .cpp
    case "m", "mm": .objectiveC
    case "js", "jsx", "mjs", "cjs": .javaScript
    case "ts", "mts", "cts": .typeScript
    case "tsx": .tsx
    case "py", "pyi": .python
    case "go": .go
    case "rs": .rust
    case "java": .java
    case "json", "jsonc": .json
    case "yaml", "yml": .yaml
    default: nil
    }
  }
}

public enum SyntaxHighlightKind: String, Hashable, Sendable {
  case comment
  case string
  case keyword
  case type
  case function
  case variable
  case number
  case operatorSymbol
  case punctuation
  case attribute
  case label
  case other
}

public struct SyntaxHighlightSpan: Hashable, Sendable {
  public let range: NSRange
  public let kind: SyntaxHighlightKind

  public init(range: NSRange, kind: SyntaxHighlightKind) {
    self.range = range
    self.kind = kind
  }
}

public struct SyntaxHighlightResult: Hashable, Sendable {
  public let language: SyntaxLanguage
  public let spans: [SyntaxHighlightSpan]

  public init(
    language: SyntaxLanguage,
    spans: [SyntaxHighlightSpan]
  ) {
    self.language = language
    self.spans = spans
  }
}

private enum SyntaxHighlightConfigurationError: Error {
  case queryBundleNotFound(String)
}

public actor SyntaxHighlightService {
  private struct ParsedDocument {
    let language: SyntaxLanguage
    let text: String
    let tree: MutableTree
  }

  public static let shared = SyntaxHighlightService()
  public static let maximumUTF16Length = 512 * 1024
  public static let maximumCaptureCount = 100_000

  private var configurations: [SyntaxLanguage: LanguageConfiguration] = [:]
  private var parsedDocuments: [ParsedDocument] = []

  public init() {}

  public func highlights(
    in text: String,
    path: GitPath,
    visibleRange: NSRange? = nil
  ) throws -> SyntaxHighlightResult? {
    guard
      !text.isEmpty,
      text.utf16.count <= Self.maximumUTF16Length,
      let language = SyntaxLanguage.detect(path: path)
    else {
      return nil
    }

    let configuration = try configuration(for: language)
    guard let query = configuration.queries[.highlights] else {
      return SyntaxHighlightResult(language: language, spans: [])
    }
    guard
      let tree = try parsedTree(
        for: text,
        language: language,
        configuration: configuration
      )
    else {
      return SyntaxHighlightResult(language: language, spans: [])
    }
    guard !Task.isCancelled else { return nil }

    let textRange = NSRange(location: 0, length: text.utf16.count)
    let requestedRange =
      visibleRange.map {
        NSIntersectionRange($0, textRange)
      } ?? textRange
    guard requestedRange.length > 0 else {
      return SyntaxHighlightResult(language: language, spans: [])
    }

    let cursor = query.execute(in: tree)
    cursor.setRange(requestedRange)
    let ranges =
      cursor
      .resolve(with: .init(string: text))
      .highlights()
      .prefix(Self.maximumCaptureCount)

    let spans = ranges.compactMap { namedRange -> SyntaxHighlightSpan? in
      let range = NSIntersectionRange(namedRange.range, textRange)
      guard range.length > 0 else { return nil }
      return SyntaxHighlightSpan(
        range: range,
        kind: Self.kind(for: namedRange.nameComponents)
      )
    }
    return SyntaxHighlightResult(language: language, spans: spans)
  }

  private func parsedTree(
    for text: String,
    language: SyntaxLanguage,
    configuration: LanguageConfiguration
  ) throws -> MutableTree? {
    if let index = parsedDocuments.firstIndex(where: {
      $0.language == language && $0.text == text
    }) {
      let cached = parsedDocuments.remove(at: index)
      parsedDocuments.append(cached)
      return cached.tree
    }

    let parser = Parser()
    parser.timeout = 0.25
    try parser.setLanguage(configuration.language)
    guard let tree = parser.parse(text) else { return nil }
    parsedDocuments.append(
      ParsedDocument(language: language, text: text, tree: tree)
    )
    if parsedDocuments.count > 4 {
      parsedDocuments.removeFirst(parsedDocuments.count - 4)
    }
    return tree
  }

  private func configuration(
    for language: SyntaxLanguage
  ) throws -> LanguageConfiguration {
    if let configuration = configurations[language] {
      return configuration
    }
    let configuration: LanguageConfiguration
    switch language {
    case .swift:
      configuration = try makeConfiguration(
        tree_sitter_swift(),
        name: "Swift"
      )
    case .c:
      configuration = try makeConfiguration(tree_sitter_c(), name: "C")
    case .cpp:
      configuration = try makeConfiguration(tree_sitter_cpp(), name: "CPP")
    case .objectiveC:
      configuration = try makeConfiguration(
        tree_sitter_objc(),
        name: "Objc"
      )
    case .javaScript:
      configuration = try makeConfiguration(
        tree_sitter_javascript(),
        name: "JavaScript"
      )
    case .typeScript:
      configuration = try makeConfiguration(
        tree_sitter_typescript(),
        name: "TypeScript"
      )
    case .tsx:
      configuration = try makeConfiguration(
        tree_sitter_tsx(),
        name: "TSX",
        bundleName: "TreeSitterTypeScript_TreeSitterTSX"
      )
    case .python:
      configuration = try makeConfiguration(
        tree_sitter_python(),
        name: "Python"
      )
    case .go:
      configuration = try makeConfiguration(tree_sitter_go(), name: "Go")
    case .rust:
      configuration = try makeConfiguration(
        tree_sitter_rust(),
        name: "Rust"
      )
    case .java:
      configuration = try makeConfiguration(
        tree_sitter_java(),
        name: "Java"
      )
    case .json:
      configuration = try makeConfiguration(
        tree_sitter_json(),
        name: "JSON"
      )
    case .yaml:
      configuration = try makeConfiguration(
        tree_sitter_yaml(),
        name: "YAML"
      )
    }
    configurations[language] = configuration
    return configuration
  }

  private func makeConfiguration(
    _ language: OpaquePointer,
    name: String,
    bundleName: String? = nil
  ) throws -> LanguageConfiguration {
    let resolvedBundleName =
      bundleName ?? "TreeSitter\(name)_TreeSitter\(name)"
    guard let queryDirectory = queryDirectory(for: resolvedBundleName) else {
      throw SyntaxHighlightConfigurationError.queryBundleNotFound(
        resolvedBundleName
      )
    }
    return try LanguageConfiguration(
      language,
      name: name,
      queriesURL: queryDirectory
    )
  }

  /// Swift Testing runs package tests from Xcode's `swift/pm` executable, so
  /// `Bundle.main` is not the test product. Resolve dependency resources from
  /// both normal app bundle locations and a bounded set of executable parents.
  private func queryDirectory(for bundleName: String) -> URL? {
    var containers = [
      Bundle.main.resourceURL,
      Bundle.main.bundleURL,
      Bundle.main.bundleURL.deletingLastPathComponent(),
    ].compactMap(\.self)
    for bundle in Bundle.allBundles + Bundle.allFrameworks {
      containers.append(
        contentsOf: [
          bundle.resourceURL,
          bundle.bundleURL,
          bundle.bundleURL.deletingLastPathComponent(),
        ].compactMap(\.self))
    }
    let workingDirectory = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true
    )
    containers.append(
      workingDirectory.appendingPathComponent(".build/debug", isDirectory: true)
    )
    containers.append(
      workingDirectory.appendingPathComponent(".build/release", isDirectory: true)
    )

    var executableDirectory =
      URL(fileURLWithPath: CommandLine.arguments[0])
      .standardizedFileURL
      .deletingLastPathComponent()
    for _ in 0..<6 {
      containers.append(executableDirectory)
      executableDirectory.deleteLastPathComponent()
    }

    var checkedPaths = Set<String>()
    for container in containers {
      let standardizedContainer = container.standardizedFileURL
      guard checkedPaths.insert(standardizedContainer.path).inserted else {
        continue
      }
      let bundleURL =
        standardizedContainer
        .appendingPathComponent("\(bundleName).bundle", isDirectory: true)
      let candidates = [
        bundleURL.appendingPathComponent(
          "Contents/Resources/queries",
          isDirectory: true
        ),
        bundleURL.appendingPathComponent("queries", isDirectory: true),
      ]
      if let readable = candidates.first(where: {
        FileManager.default.isReadableFile(atPath: $0.path)
      }) {
        return readable
      }
    }
    return nil
  }

  private static func kind(
    for nameComponents: [String]
  ) -> SyntaxHighlightKind {
    guard let root = nameComponents.first else { return .other }
    return switch root {
    case "comment": .comment
    case "string", "character": .string
    case "keyword", "conditional", "repeat", "exception", "include": .keyword
    case "type", "constructor", "module", "namespace": .type
    case "function", "method": .function
    case "variable", "property", "constant", "parameter": .variable
    case "number", "float", "boolean": .number
    case "operator": .operatorSymbol
    case "punctuation": .punctuation
    case "attribute", "tag": .attribute
    case "label": .label
    default: .other
    }
  }
}
