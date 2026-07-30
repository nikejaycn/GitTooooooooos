import SwiftUI

/// A deterministic three-region workspace layout.
///
/// Top and bottom chrome keep their intrinsic heights at the window edges.
/// The middle region receives every remaining point and owns its scrolling.
/// Keeping this contract in one view prevents individual workspaces from
/// competing for height or growing beyond the content boundary.
struct CurrentContentLayout<Top: View, Middle: View, Bottom: View>: View {
  private let separatesTop: Bool
  private let separatesBottom: Bool
  private let top: Top
  private let middle: Middle
  private let bottom: Bottom

  init(
    separatesTop: Bool = true,
    separatesBottom: Bool = true,
    @ViewBuilder top: () -> Top,
    @ViewBuilder middle: () -> Middle,
    @ViewBuilder bottom: () -> Bottom
  ) {
    self.separatesTop = separatesTop
    self.separatesBottom = separatesBottom
    self.top = top()
    self.middle = middle()
    self.bottom = bottom()
  }

  var body: some View {
    VStack(spacing: 0) {
      top
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)

      if separatesTop {
        Divider()
      }

      middle
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .clipped()

      if separatesBottom {
        Divider()
      }

      bottom
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }
}
