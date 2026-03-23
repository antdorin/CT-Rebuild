import SwiftUI

// MARK: - Panel State

enum Panel: Equatable {
    case none, left, right, top, bottom
}

// MARK: - Dashboard View

struct DashboardView: View {
    @State private var activePanel: Panel = .none
    @State private var longPressActive: Bool = false
    private let screen = UIScreen.main.bounds

    /// Reads the real device safe-area insets from UIKit.
    /// geo.safeAreaInsets returns zero when the GeometryReader lives inside
    /// .ignoresSafeArea(), so we bypass SwiftUI and read directly from the
    /// window scene instead.
    private var uiSafeInsets: EdgeInsets {
        let insets = (UIApplication.shared.connectedScenes.first as? UIWindowScene)
            ?.keyWindow?.safeAreaInsets ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left,
                          bottom: insets.bottom, trailing: insets.right)
    }

    var body: some View {
        // GeometryReader ignores safe area so panels slide in from the true
        // physical edges (behind notch / home indicator). Safe area insets are
        // read from `geo` and passed explicitly to each content view so that
        // text and interactive elements are never obscured.
        GeometryReader { geo in
            let safe = uiSafeInsets

            ZStack {
                // ── Adaptive Background — black in dark mode, white in light ──
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                // ── Placeholder Dashboard Content ─────────────────────────────
                placeholderContent(safeArea: safe)

                // ── Dim Backdrop (tap anywhere to dismiss) ────────────────────
                if activePanel != .none {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { activePanel = .none }
                        .transition(.opacity)
                        .zIndex(10)
                }

                // ── Left Panel (swipe RIGHT to open) ──────────────────────────
                if activePanel == .left {
                    panelContent(for: .left, safeArea: safe)
                        .frame(width: screen.width * 0.97, height: screen.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .zIndex(11)
                        .transition(.move(edge: .leading))
                }

                // ── Right Panel (swipe LEFT to open) ──────────────────────────
                if activePanel == .right {
                    panelContent(for: .right, safeArea: safe)
                        .frame(width: screen.width * 0.97, height: screen.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .zIndex(11)
                        .transition(.move(edge: .trailing))
                }

                // ── Top Panel (swipe DOWN to open) ────────────────────────────
                if activePanel == .top {
                    panelContent(for: .top, safeArea: safe)
                        .frame(width: screen.width, height: screen.height * 0.97)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(11)
                        .transition(.move(edge: .top))
                }

                // ── Bottom Panel (swipe UP to open) ───────────────────────────
                if activePanel == .bottom {
                    panelContent(for: .bottom, safeArea: safe)
                        .frame(width: screen.width, height: screen.height * 0.97)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .zIndex(11)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.07), value: activePanel)
            // LongPress fires haptic immediately at 0.07 s (no sequencing delay).
            // Drag reads longPressActive to decide threshold + switch behaviour.
            // simultaneousGesture ensures close swipe fires even when child views
            // (e.g. left-panel grid) have their own DragGestures active.
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(longPressHapticGesture)
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    // MARK: - Placeholder Content

    private func placeholderContent(safeArea: EdgeInsets) -> some View {
        VStack {
            Spacer()
            Image("CTHelmet")
                .resizable()
                .scaledToFit()
                .frame(width: 320, height: 320)
            Spacer()
        }
        .padding(.top, safeArea.top)
        .padding(.bottom, safeArea.bottom)
        .padding(.leading, safeArea.leading)
        .padding(.trailing, safeArea.trailing)
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(for panel: Panel, safeArea: EdgeInsets) -> some View {
        switch panel {
        case .left:
            LeftPanelView(safeArea: safeArea)
        case .top:
            TopPanelView(safeArea: safeArea)
        case .bottom:
            BottomPanelView(safeArea: safeArea)
        case .right:
            RightPanelView(safeArea: safeArea)
        default:
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    // MARK: - Drag Gesture
    // minimumDistance: 10 — the 40 pt threshold for plain swipes is enforced
    // inside resolveSwipe so long-press+drag stays responsive at low distances.

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let wasLongPress = longPressActive
                longPressActive = false
                resolveSwipe(value: value, allowSwitch: wasLongPress)
            }
    }

    // MARK: - Long Press Haptic Gesture
    // Fires immediately when 0.1 s elapses — no sequencing, no extra touch needed.

    private var longPressHapticGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.1)
            .onEnded { _ in
                longPressActive = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
    }

    // MARK: - Shared Resolution

    private func resolveSwipe(value: DragGesture.Value, allowSwitch: Bool) {
        let dx = value.translation.width
        let dy = value.translation.height
        let adx = abs(dx)
        let ady = abs(dy)

        // Plain swipe with a panel open: only handle the close direction
        if !allowSwitch, activePanel != .none {
            let t: CGFloat = 50
            switch activePanel {
            case .left   where dx < -t && adx > ady: activePanel = .none
            case .right  where dx >  t && adx > ady: activePanel = .none
            case .top    where dy < -t && ady > adx: activePanel = .none
            // Bottom panel: require fast flick (predictedEnd > 200) to avoid triggering on slow zoom drag
            case .bottom where dy > t && ady > adx && value.predictedEndTranslation.height > 200: activePanel = .none
            default: break
            }
            return
        }

        let threshold: CGFloat = allowSwitch ? 10 : 40
        guard max(adx, ady) > threshold else { return }

        let target: Panel = adx >= ady
            ? (dx > 0 ? .left  : .right)
            : (dy > 0 ? .top   : .bottom)

        // Long-press can switch panels; plain swipe only opens from closed
        if allowSwitch || activePanel == .none {
            activePanel = target
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}
