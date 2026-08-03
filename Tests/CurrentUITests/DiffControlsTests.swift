import Foundation
import Testing

@testable import CurrentUI

@Suite("Diff file previews")
struct DiffControlsTests {
  @Test("Reads image format, pixel dimensions, size, and frame count")
  func imageMetadata() throws {
    let png = try #require(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )

    let metadata = try #require(ImagePreviewMetadata.read(from: png))

    #expect(metadata.format == "PNG")
    #expect(metadata.pixelSize == "1 × 1 px")
    #expect(!metadata.fileSize.isEmpty)
    #expect(metadata.frameCount == 1)
  }

  @Test("Rejects data that is not a supported image")
  func invalidImageMetadata() {
    #expect(ImagePreviewMetadata.read(from: Data("not an image".utf8)) == nil)
  }
}
