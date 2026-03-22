import SwiftUI

// MARK: - Slide-forward / slide-back animation curves
// Mirrors the CSS translateZ animations: slide-fwd-center / slide-bck-center

extension Animation {
    /// Page enters forward (small → normal size). easeOutQuad, 0.45s.
    static let slideFwd = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.45)
    /// Page exits backward (normal → small). easeInSine, 0.45s.
    static let slideBck = Animation.timingCurve(0.47, 0.00, 0.745, 0.715, duration: 0.45)
}

// MARK: - Page transition

/// Full-page content: zooms forward when entering (select), shrinks back when exiting (double-tap).
extension AnyTransition {
    static var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active:   _ScaleFade(scale: 0.82, opacity: 0),
                identity: _ScaleFade(scale: 1.0,  opacity: 1)
            ),
            removal: .modifier(
                active:   _ScaleFade(scale: 0.65, opacity: 0),
                identity: _ScaleFade(scale: 1.0,  opacity: 1)
            )
        )
    }
}

struct _ScaleFade: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.scaleEffect(scale).opacity(opacity)
    }
}
