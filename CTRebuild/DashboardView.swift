import SwiftUI

// MARK: - Panel State

enum Panel: Equatable {
    case none, left, right, top, bottom
}

// MARK: - Dashboard View

struct DashboardView: View {
    @State private var activePanel: Panel = .none

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
                // 97% wide × 94% tall (3% margin top, bottom, right)
                if activePanel == .left {
                    panelContent(label: "Left Panel", safeArea: safe)
                        .frame(width: geo.size.width * 0.97, height: geo.size.height * 0.94)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .zIndex(11)
                        .transition(.move(edge: .leading))
                }

                // ── Right Panel (swipe LEFT to open) ──────────────────────────
                // 97% wide × 94% tall (3% margin top, bottom, left)
                if activePanel == .right {
                    panelContent(label: "Right Panel", safeArea: safe)
                        .frame(width: geo.size.width * 0.97, height: geo.size.height * 0.94)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .zIndex(11)
                        .transition(.move(edge: .trailing))
                }

                // ── Top Panel (swipe DOWN to open) ────────────────────────────
                // 94% wide × 97% tall (3% margin left, right, bottom)
                if activePanel == .top {
                    panelContent(label: "Top Panel", safeArea: safe)
                        .frame(width: geo.size.width * 0.94, height: geo.size.height * 0.97)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(11)
                        .transition(.move(edge: .top))
                }

                // ── Bottom Panel (swipe UP to open) ───────────────────────────
                // 94% wide × 97% tall (3% margin left, right, top)
                if activePanel == .bottom {
                    panelContent(label: "Bottom Panel", safeArea: safe)
                        .frame(width: geo.size.width * 0.94, height: geo.size.height * 0.97)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .zIndex(11)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: activePanel)
            .gesture(swipeGesture)
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

    private func panelContent(label: String, safeArea: EdgeInsets) -> some View {
        ZStack(alignment: .topLeading) {
            // Translucent material — ignores safe area so blur fills panel edge-to-edge
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                    // Content respects notch / status bar
                    .padding(.top, safeArea.top + 16)
                    .padding(.horizontal, max(safeArea.leading, 24))
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)
                    .padding(.top, 14)
                Spacer()
            }
            .padding(.bottom, safeArea.bottom)
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let adx = abs(dx)
                let ady = abs(dy)

                // Dismiss open panel on reverse swipe
                if activePanel != .none {
                    let threshold: CGFloat = 50
                    switch activePanel {
                    case .left   where dx < -threshold && adx > ady: activePanel = .none
                    case .right  where dx >  threshold && adx > ady: activePanel = .none
                    case .top    where dy < -threshold && ady > adx: activePanel = .none
                    case .bottom where dy >  threshold && ady > adx: activePanel = .none
                    default: break
                    }
                    return
                }

                // Open panel based on dominant swipe direction
                let threshold: CGFloat = 40
                guard max(adx, ady) > threshold else { return }

                if adx >= ady {
                    activePanel = dx > 0 ? .left : .right
                } else {
                    activePanel = dy > 0 ? .top : .bottom
                }
            }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}
