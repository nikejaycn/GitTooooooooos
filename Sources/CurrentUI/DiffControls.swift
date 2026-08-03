import AppKit
import CurrentDomain
import DiffKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct DiffDocumentView: View {
  let document: DiffDocument
  let presentation: DiffPresentation
  let preview: FilePreviewContent?
  let textConfiguration: DiffTextConfiguration

  init(
    document: DiffDocument,
    presentation: DiffPresentation,
    preview: FilePreviewContent? = nil,
    textConfiguration: DiffTextConfiguration = DiffTextConfiguration()
  ) {
    self.document = document
    self.presentation = presentation
    self.preview = preview
    self.textConfiguration = textConfiguration
  }

  @ViewBuilder
  var body: some View {
    if document.isBinary {
      BinaryFilePreviewView(document: document, preview: preview)
    } else {
      switch presentation {
      case .unified:
        DiffTextView(
          document: document,
          configuration: textConfiguration
        )
      case .split:
        VStack(spacing: 0) {
          HStack(spacing: 0) {
            Label("Before", systemImage: "minus")
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 10)
            Divider()
            Label("After", systemImage: "plus")
              .foregroundStyle(.green)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 10)
          }
          .font(.caption.weight(.semibold))
          .frame(height: 28)
          .background(.bar)
          Divider()
          SplitDiffTextView(
            document: document,
            configuration: textConfiguration
          )
        }
      }
    }
  }
}

struct ImagePreviewMetadata: Equatable {
  let format: String
  let pixelSize: String
  let fileSize: String
  let frameCount: Int

  static func read(from data: Data) -> ImagePreviewMetadata? {
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any]
    else {
      return nil
    }
    let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
    let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    let typeIdentifier = CGImageSourceGetType(source) as String?
    let type = typeIdentifier.flatMap(UTType.init)
    let format =
      type?.preferredFilenameExtension?.uppercased()
      ?? type?.localizedDescription
      ?? "Image"
    let pixelSize =
      if let width, let height {
        "\(width) × \(height) px"
      } else {
        "Unknown dimensions"
      }
    return ImagePreviewMetadata(
      format: format,
      pixelSize: pixelSize,
      fileSize: ByteCountFormatter.string(
        fromByteCount: Int64(data.count),
        countStyle: .file
      ),
      frameCount: CGImageSourceGetCount(source)
    )
  }
}

private struct BinaryFilePreviewView: View {
  let document: DiffDocument
  let preview: FilePreviewContent?

  var body: some View {
    if let preview,
      let image = NSImage(data: preview.data),
      let metadata = ImagePreviewMetadata.read(from: preview.data)
    {
      VStack(spacing: 0) {
        HStack(spacing: 14) {
          metadataItem("Format", value: metadata.format)
          metadataItem("Dimensions", value: metadata.pixelSize)
          metadataItem("File Size", value: metadata.fileSize)
          if metadata.frameCount > 1 {
            metadataItem("Frames", value: metadata.frameCount.formatted())
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(.bar)
        Divider()
        GeometryReader { geometry in
          ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
              .resizable()
              .interpolation(.high)
              .scaledToFit()
              .frame(
                width: max(geometry.size.width - 48, 160),
                height: max(geometry.size.height - 48, 120)
              )
              .padding(24)
          }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
      }
    } else {
      unsupportedPreview
    }
  }

  private func metadataItem(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.monospacedDigit())
        .lineLimit(1)
    }
  }

  private var unsupportedPreview: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "doc.questionmark")
          .font(.system(size: 28))
          .foregroundStyle(.secondary)
          .frame(width: 38)
        VStack(alignment: .leading, spacing: 5) {
          Text("Preview Unavailable")
            .font(.title3.weight(.semibold))
          Text(
            "GitCurrent detected a binary file, but this format or file state cannot be previewed."
          )
          .foregroundStyle(.secondary)
          Text(document.path.displayString)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
        }
      }
      Text("The file can still be managed with Git; only the visual preview is unavailable.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
      Spacer(minLength: 0)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct DiffWhitespaceMenu: View {
  let options: DiffOptions
  let setOptions: (DiffOptions) -> Void

  var body: some View {
    Menu {
      Toggle(
        "Ignore Whitespace Changes",
        isOn: Binding(
          get: { options.ignoresWhitespaceChanges },
          set: { enabled in
            setOptions(
              DiffOptions(
                ignoresWhitespaceChanges: enabled,
                ignoresEndOfLineWhitespace: options.ignoresEndOfLineWhitespace
              )
            )
          }
        )
      )
      Toggle(
        "Ignore End-of-Line Whitespace",
        isOn: Binding(
          get: { options.ignoresEndOfLineWhitespace },
          set: { enabled in
            setOptions(
              DiffOptions(
                ignoresWhitespaceChanges: options.ignoresWhitespaceChanges,
                ignoresEndOfLineWhitespace: enabled
              )
            )
          }
        )
      )
    } label: {
      Image(systemName: "textformat")
    }
    .menuStyle(.borderlessButton)
    .help("Diff whitespace options")
    .accessibilityLabel("Diff whitespace options")
  }
}
