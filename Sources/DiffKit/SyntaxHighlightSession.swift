import AppKit
import CurrentDomain
import Foundation

struct SyntaxHighlightTarget {
  let textView: NSTextView
  let projection: SyntaxHighlightProjection
}

@MainActor
final class SyntaxHighlightSession {
  private struct Job: Sendable {
    let index: Int
    let path: GitPath
    let projection: SyntaxHighlightProjection
    let renderedVisibleRange: NSRange
    let sourceVisibleRange: NSRange
  }

  private struct Output: Sendable {
    let index: Int
    let spans: [RenderedSyntaxSpan]
  }

  private var generation = 0
  private var targets: [SyntaxHighlightTarget] = []
  private var path = GitPath("")
  private var task: Task<Void, Never>?
  private var appliedRanges: [[NSRange]] = []

  func update(
    path: GitPath,
    targets: [SyntaxHighlightTarget]
  ) {
    generation &+= 1
    task?.cancel()
    restoreBaseColors()
    self.path = path
    self.targets = targets
    appliedRanges = Array(repeating: [], count: targets.count)
  }

  func highlightVisibleRanges() {
    generation &+= 1
    let requestedGeneration = generation
    task?.cancel()

    let jobs = targets.enumerated().compactMap { index, target -> Job? in
      let renderedVisibleRange = target.textView.syntaxHighlightVisibleRange
      guard
        let sourceVisibleRange = target.projection.sourceRange(
          intersecting: renderedVisibleRange
        )
      else {
        return nil
      }
      return Job(
        index: index,
        path: path,
        projection: target.projection,
        renderedVisibleRange: renderedVisibleRange,
        sourceVisibleRange: sourceVisibleRange
      )
    }

    guard !jobs.isEmpty else {
      restoreBaseColors()
      return
    }

    task = Task(priority: .utility) { [weak self] in
      var outputs: [Output] = []
      for job in jobs {
        guard !Task.isCancelled else { return }
        do {
          let result = try await SyntaxHighlightService.shared.highlights(
            in: job.projection.sourceText,
            path: job.path,
            visibleRange: job.sourceVisibleRange
          )
          guard !Task.isCancelled else { return }
          outputs.append(
            Output(
              index: job.index,
              spans: job.projection.render(
                result?.spans ?? [],
                within: job.renderedVisibleRange
              )
            )
          )
        } catch {
          outputs.append(Output(index: job.index, spans: []))
        }
      }
      guard !Task.isCancelled else { return }
      self?.apply(outputs, generation: requestedGeneration)
    }
  }

  func cancel() {
    generation &+= 1
    task?.cancel()
    task = nil
  }

  private func apply(
    _ outputs: [Output],
    generation requestedGeneration: Int
  ) {
    guard requestedGeneration == generation else { return }
    restoreBaseColors()

    for output in outputs where targets.indices.contains(output.index) {
      let textStorage = targets[output.index].textView.textStorage
      let length = textStorage?.length ?? 0
      textStorage?.beginEditing()
      for span in output.spans
      where span.range.location >= 0
        && span.range.length > 0
        && NSMaxRange(span.range) <= length
      {
        textStorage?.addAttribute(
          .foregroundColor,
          value: color(for: span.kind),
          range: span.range
        )
        appliedRanges[output.index].append(span.range)
      }
      textStorage?.endEditing()
    }
  }

  private func restoreBaseColors() {
    for index in targets.indices where appliedRanges.indices.contains(index) {
      guard !appliedRanges[index].isEmpty else { continue }
      let textStorage = targets[index].textView.textStorage
      let length = textStorage?.length ?? 0
      textStorage?.beginEditing()
      for range in appliedRanges[index]
      where range.location >= 0 && NSMaxRange(range) <= length {
        textStorage?.addAttribute(
          .foregroundColor,
          value: NSColor.textColor,
          range: range
        )
      }
      textStorage?.endEditing()
      appliedRanges[index].removeAll(keepingCapacity: true)
    }
  }

  private func color(for kind: SyntaxHighlightKind) -> NSColor {
    switch kind {
    case .comment:
      .secondaryLabelColor
    case .string:
      .systemRed
    case .keyword:
      .systemPink
    case .type:
      .systemTeal
    case .function:
      .systemPurple
    case .variable:
      .textColor
    case .number:
      .systemOrange
    case .operatorSymbol:
      .systemIndigo
    case .punctuation:
      .secondaryLabelColor
    case .attribute:
      .systemYellow
    case .label:
      .systemBlue
    case .other:
      .textColor
    }
  }
}

extension NSTextView {
  fileprivate var syntaxHighlightVisibleRange: NSRange {
    let length = textStorage?.length ?? 0
    guard length > 0 else { return NSRange(location: 0, length: 0) }
    guard let clipView = enclosingScrollView?.contentView else {
      return NSRange(location: 0, length: min(length, 12_000))
    }

    let visibleRect = clipView.documentVisibleRect
    let horizontalPoint = textContainerInset.width + 1
    let first = characterIndexForInsertion(
      at: NSPoint(x: horizontalPoint, y: visibleRect.minY)
    )
    let last = characterIndexForInsertion(
      at: NSPoint(x: horizontalPoint, y: visibleRect.maxY)
    )
    let preload = 4_000
    let lowerBound = max(0, min(first, last) - preload)
    let upperBound = min(length, max(first, last) + preload)
    return NSRange(
      location: lowerBound,
      length: max(0, upperBound - lowerBound)
    )
  }
}
