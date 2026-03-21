import SwiftUI

// MARK: - Panel State

enum Panel: Equatable {
    case none, left, right, top, bottom
}

// MARK: - Dashboard View

struct DashboardView: View {
    @State private var activePanel: Panel = .none

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Black Background ─────────────────────────────────────────
                Color.black
                    .ignoresSafeArea()

                // ── Placeholder Dashboard Content ─────────────────────────────
                placeholderContent

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
                    HStack(spacing: 0) {
                        panelContent(label: "Left Panel")
                            .frame(width: geo.size.width * 0.78)
                        Spacer(minLength: 0)
                    }
                    .zIndex(11)
                    .transition(.move(edge: .leading))
                }

                // ── Right Panel (swipe LEFT to open) ──────────────────────────
                if activePanel == .right {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        panelContent(label: "Right Panel")
                            .frame(width: geo.size.width * 0.78)
                    }
                    .zIndex(11)
                    .transition(.move(edge: .trailing))
                }

                // ── Top Panel (swipe DOWN to open) ────────────────────────────
                if activePanel == .top {
                    VStack(spacing: 0) {
                        panelContent(label: "Top Panel")
                            .frame(height: geo.size.height * 0.55)
                        Spacer(minLength: 0)
                    }
                    .zIndex(11)
                    .transition(.move(edge: .top))
                }

                // ── Bottom Panel (swipe UP to open) ───────────────────────────
                if activePanel == .bottom {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        panelContent(label: "Bottom Panel")
                            .frame(height: geo.size.height * 0.55)
                    }
                    .zIndex(11)
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: activePanel)
            .gesture(swipeGesture)
        }
        .ignoresSafeArea()
    }

    // MARK: - Placeholder Content

    private var placeholderContent: some View {
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
    }

    // MARK: - Panel Content

    private func panelContent(label: String) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.07, green: 0.07, blue: 0.09)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 64)
                    .padding(.horizontal, 24)
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.top, 14)
                Spacer()
            }
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
