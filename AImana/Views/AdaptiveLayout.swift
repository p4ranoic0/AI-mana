import AImanaCore
import SwiftUI

/// iPad (regular width) layout constants. The compact path never reads these, so iPhone layouts stay as they were.
enum AdaptiveLayout {
    /// Widest the dashboard and Costs grow: past this, cards get stretched lines that are hard to read.
    static let maxContentWidth: CGFloat = 1180
    /// Smallest card width in the dashboard/Costs grids: about an iPhone card, so 2 columns from ~700 pt, 3 on very
    /// wide windows.
    static let minCardWidth: CGFloat = 340
    /// Single-column screens (provider detail in a narrow window) stay at a readable measure.
    static let readableWidth: CGFloat = 720
    /// Provider detail splits into two columns from this container width.
    static let twoColumnWidth: CGFloat = 860
    /// The floating bottom bar keeps roughly its iPhone proportions instead of spanning the whole window.
    static let bottomBarMaxWidth: CGFloat = 520
    /// Keeps the overview lanes readable within the centred ring-and-details group.
    static let heroDetailsMaxWidth: CGFloat = 460

    static func gridColumns(spacing: CGFloat = SoftTheme.Space.lg) -> [GridItem] {
        [GridItem(.adaptive(minimum: minCardWidth), spacing: spacing, alignment: .top)]
    }
}

extension View {
    /// Caps the width and centres the content; used only on the regular-width path.
    func centeredMaxWidth(_ width: CGFloat) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
