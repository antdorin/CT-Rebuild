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

    var body: some View {
        // GeometryReader ignores safe area so panels slide in from the true
        // physical edges (behind notch / home indicator). Safe area insets are
        // read from `geo` and passed explicitly to each content view so that
        // text and interactive elements are never obscured.
        GeometryReader { geo in
            let safe = geo.safeAreaInsets

            ZStack {
                // ── Black Background — bleeds to all edges ────────────────────
                Color.black
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
            .animation(.easeInOut(duration: 0.2), value: activePanel)
            // ExclusiveGesture: hold+drag takes priority over plain swipe
            .gesture(ExclusiveGesture(longPressSwipeGesture, swipeGesture))
        }
        .ignoresSafeArea()
    }

    // MARK: - Placeholder Content

    private func placeholderContent(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.05))
            Text("DASHBOARD")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.07))
                .tracking(6)
            Spacer()
        }
        // Keep content away from notch and home indicator
        .padding(.top, safeArea.top)
        .padding(.bottom, safeArea.bottom)
        .padding(.leading, safeArea.leading)
        .padding(.trailing, safeArea.trailing)
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(for panel: Panel, safeArea: EdgeInsets) -> some View {
        switch panel {
        case .bottom:
            BottomPanelView(safeArea: safeArea)
        default:
            // Translucent material — ignores safe area so blur fills panel edge-to-edge
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    // MARK: - Plain Swipe Gesture
    // Opens a panel from closed state; closes on reverse swipe.

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                resolveSwipe(translation: value.translation, allowSwitch: false)
            }
    }

    // MARK: - Long Press + Swipe Gesture
    // Hold 0.0005 s → haptic fires → drag to open or switch any panel directly.

    private var longPressSwipeGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.005)
            .sequenced(before: DragGesture(minimumDistance: 10))
            .onChanged { state in
                if case .first(true) = state, !longPressActive {
                    longPressActive = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { state in
                defer { longPressActive = false }
                guard case .second(true, let drag?) = state else { return }
                resolveSwipe(translation: drag.translation, allowSwitch: true)
            }
    }

    // MARK: - Shared Resolution

    private func resolveSwipe(translation: CGSize, allowSwitch: Bool) {
        let dx = translation.width
        let dy = translation.height
        let adx = abs(dx)
        let ady = abs(dy)

        // Plain swipe with a panel open: only handle the close direction
        if !allowSwitch, activePanel != .none {
            let t: CGFloat = 50
            switch activePanel {
            case .left   where dx < -t && adx > ady: activePanel = .none
            case .right  where dx >  t && adx > ady: activePanel = .none
            case .top    where dy < -t && ady > adx: activePanel = .none
            case .bottom where dy >  t && ady > adx: activePanel = .none
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
