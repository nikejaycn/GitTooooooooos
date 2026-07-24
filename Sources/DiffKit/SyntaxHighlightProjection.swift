import Foundation

public struct SyntaxRangeMapping: Hashable, Sendable {
  public let sourceRange: NSRange
  public let renderedRange: NSRange

  public init(sourceRange: NSRange, renderedRange: NSRange) {
    self.sourceRange = sourceRange
    self.renderedRange = renderedRange
  }
}

public struct RenderedSyntaxSpan: Hashable, Sendable {
  public let range: NSRange
  public let kind: SyntaxHighlightKind

  public init(range: NSRange, kind: SyntaxHighlightKind) {
    self.range = range
    self.kind = kind
  }
}

/// Maps parser ranges in a reconstructed old/new source document back into
/// TextKit's rendered diff ranges, which include gutters and change markers.
public struct SyntaxHighlightProjection: Hashable, Sendable {
  public let sourceText: String
  public let mappings: [SyntaxRangeMapping]

  public init(sourceText: String, mappings: [SyntaxRangeMapping]) {
    self.sourceText = sourceText
    self.mappings = mappings
  }

  public func sourceRange(
    intersecting renderedRange: NSRange
  ) -> NSRange? {
    var lowerBound: Int?
    var upperBound: Int?
    for mapping in mappings
    where NSIntersectionRange(mapping.renderedRange, renderedRange).length > 0 {
      lowerBound = min(lowerBound ?? mapping.sourceRange.location, mapping.sourceRange.location)
      upperBound = max(
        upperBound ?? NSMaxRange(mapping.sourceRange), NSMaxRange(mapping.sourceRange))
    }
    guard let lowerBound, let upperBound else { return nil }
    return NSRange(location: lowerBound, length: upperBound - lowerBound)
  }

  public func render(
    _ spans: [SyntaxHighlightSpan],
    within renderedRange: NSRange
  ) -> [RenderedSyntaxSpan] {
    var rendered: [RenderedSyntaxSpan] = []
    for mapping in mappings {
      let visibleMapping = NSIntersectionRange(mapping.renderedRange, renderedRange)
      guard visibleMapping.length > 0 else { continue }
      for span in spans {
        let sourceIntersection = NSIntersectionRange(
          mapping.sourceRange,
          span.range
        )
        guard sourceIntersection.length > 0 else { continue }
        let offset = sourceIntersection.location - mapping.sourceRange.location
        let translated = NSRange(
          location: mapping.renderedRange.location + offset,
          length: sourceIntersection.length
        )
        let visible = NSIntersectionRange(translated, visibleMapping)
        guard visible.length > 0 else { continue }
        rendered.append(RenderedSyntaxSpan(range: visible, kind: span.kind))
      }
    }
    return rendered
  }
}

struct SyntaxHighlightProjectionBuilder {
  private(set) var sourceText = ""
  private(set) var mappings: [SyntaxRangeMapping] = []

  mutating func append(
    _ text: String,
    renderedRange: NSRange?
  ) {
    let sourceLocation = sourceText.utf16.count
    sourceText += text
    let sourceLength = text.utf16.count
    if sourceLength > 0, let renderedRange {
      mappings.append(
        SyntaxRangeMapping(
          sourceRange: NSRange(
            location: sourceLocation,
            length: sourceLength
          ),
          renderedRange: renderedRange
        )
      )
    }
    sourceText += "\n"
  }

  func build() -> SyntaxHighlightProjection {
    SyntaxHighlightProjection(
      sourceText: sourceText,
      mappings: mappings
    )
  }
}
