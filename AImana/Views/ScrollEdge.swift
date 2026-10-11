import SwiftUI

extension View {
    /// Content scrolling under floating bar buttons and titles fades into a solid edge instead of showing through
    /// them (iOS 26 Liquid Glass bars are otherwise see-through).
    @ViewBuilder func hardTopScrollEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}
