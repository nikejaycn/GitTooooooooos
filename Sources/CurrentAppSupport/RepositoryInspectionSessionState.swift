import CurrentDomain
import DiffKit

/// State transitions for working-copy diffs, commit diffs, file history, and blame.
///
/// Keeping the selected inputs beside their results makes option-driven reloads and
/// repository-session cleanup atomic instead of coordinating unrelated optionals.
public struct RepositoryInspectionSessionState: Equatable {
  public private(set) var selectedDiff: DiffDocument?
  public private(set) var selectedDiffChange: FileChange?
  public private(set) var selectedFilePreview: FilePreviewContent?
  public private(set) var isDiffLoading = false

  public private(set) var selectedCommitDiff: DiffDocument?
  public private(set) var selectedCommitDiffFile: CommitFileChange?
  public private(set) var selectedCommitDiffComparison: CommitComparison?
  public private(set) var selectedCommitFilePreview: FilePreviewContent?
  public private(set) var isCommitDiffLoading = false

  public private(set) var fileHistory: FileHistoryResult?
  public private(set) var blameDocument: BlameDocument?
  public private(set) var isFileHistoryLoading = false
  public private(set) var isBlameLoading = false

  public init() {}

  public mutating func beginDiff(for change: FileChange) {
    selectedDiffChange = change
    selectedFilePreview = nil
    isDiffLoading = true
  }

  public mutating func finishDiff(
    with document: DiffDocument? = nil,
    preview: FilePreviewContent? = nil
  ) {
    if let document {
      selectedDiff = document
    }
    if let preview {
      selectedFilePreview = preview
    }
    isDiffLoading = false
  }

  public mutating func failDiff() {
    selectedDiff = nil
    isDiffLoading = false
  }

  public mutating func clearDiff() {
    selectedDiff = nil
    selectedDiffChange = nil
    selectedFilePreview = nil
    isDiffLoading = false
  }

  public mutating func beginCommitDiff(
    file: CommitFileChange,
    comparison: CommitComparison
  ) {
    selectedCommitDiff = nil
    selectedCommitDiffFile = file
    selectedCommitDiffComparison = comparison
    selectedCommitFilePreview = nil
    isCommitDiffLoading = true
  }

  public mutating func finishCommitDiff(
    with document: DiffDocument? = nil,
    preview: FilePreviewContent? = nil
  ) {
    if let document {
      selectedCommitDiff = document
    }
    if let preview {
      selectedCommitFilePreview = preview
    }
    isCommitDiffLoading = false
  }

  public mutating func failCommitDiff() {
    selectedCommitDiff = nil
    isCommitDiffLoading = false
  }

  public mutating func clearCommitDiff() {
    selectedCommitDiff = nil
    selectedCommitDiffFile = nil
    selectedCommitDiffComparison = nil
    selectedCommitFilePreview = nil
    isCommitDiffLoading = false
  }

  public mutating func beginFileInsights() {
    fileHistory = nil
    blameDocument = nil
    isFileHistoryLoading = true
    isBlameLoading = false
  }

  public mutating func finishFileHistory(with result: FileHistoryResult? = nil) {
    if let result {
      fileHistory = result
    }
    isFileHistoryLoading = false
  }

  public mutating func beginBlame(clearDocument: Bool) {
    if clearDocument {
      blameDocument = nil
    }
    isBlameLoading = true
  }

  @discardableResult
  public mutating func finishBlame(
    with page: BlamePage,
    appending: Bool
  ) -> Bool {
    let document: BlameDocument?
    if appending {
      document = blameDocument?.appending(page)
    } else {
      document = BlameDocument(
        generation: page.generation,
        path: page.path,
        revision: page.revision,
        lines: page.lines,
        nextLine: page.nextLine
      )
    }
    guard let document else {
      isBlameLoading = false
      return false
    }
    blameDocument = document
    isBlameLoading = false
    return true
  }

  public mutating func finishBlameLoading() {
    isBlameLoading = false
  }

  public mutating func clearFileInsights() {
    fileHistory = nil
    blameDocument = nil
    isFileHistoryLoading = false
    isBlameLoading = false
  }

  public mutating func clear() {
    clearDiff()
    clearCommitDiff()
    clearFileInsights()
  }
}
