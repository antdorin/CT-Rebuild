import SwiftUI

struct BottomPanelView: View {
    let safeArea: EdgeInsets

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Text("BOTTOM PANEL")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .tracking(6)
        }
    }
}
