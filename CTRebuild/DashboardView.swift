import SwiftUI

// MARK: - Panel State

enum Panel: Equatable {
    case none, left, right, top, bottom
}

// MARK: - Dashboard View

struct DashboardView: View {
    @State private var activePanel: Panel = .none
    private let screen = UIScreen.main.bounds
    /// How close to the screen edge a swipe must start to trigger a panel (pt).
    private let edgeZone: CGFloat = 30

    var body: some View {
        // GeometryReader ignores safe area so panels slide in from the true
        // physical edges (behind notch / home indicator). Safe area insets are
        // read from `geo` and passed explicitly to each content view so that
        // text and interactive elements are never obscured.
        GeometryReader { geo in
            let safe = geo.safeAreaInsets

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
            .simultaneousGesture(dragGesture)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                resolveSwipe(value: value)
            }
    }

    // MARK: - Shared Resolution

    private func resolveSwipe(value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        let adx = abs(dx)
        let ady = abs(dy)

        // ── Close an open panel (swipe it back) ──────────────────────────
        if activePanel != .none {
            let t: CGFloat = 50
            switch activePanel {
            case .left   where dx < -t && adx > ady: activePanel = .none
            case .right  where dx >  t && adx > ady: activePanel = .none
            case .top    where dy < -t && ady > adx: activePanel = .none
            case .bottom where dy > t && ady > adx && value.predictedEndTranslation.height > 200:
                activePanel = .none
            default: break
            }
            return
        }

        // ── Open a panel (swipe must start near the corresponding edge) ──
        let start = value.startLocation
        let threshold: CGFloat = 40
        guard max(adx, ady) > threshold else { return }

        if adx >= ady {
            // Horizontal swipe
            if dx > 0 && start.x < edgeZone {
                activePanel = .left
            } else if dx < 0 && start.x > screen.width - edgeZone {
                activePanel = .right
            }
        } else {
            // Vertical swipe
            if dy > 0 && start.y < edgeZone {
                activePanel = .top
            } else if dy < 0 && start.y > screen.height - edgeZone {
                activePanel = .bottom
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}
