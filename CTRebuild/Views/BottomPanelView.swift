import SwiftUI

struct BottomPanelView: View {
    let safeArea: EdgeInsets

    @StateObject private var vm = CameraViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            // ── Translucent background — full bleed ───────────────────────────
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // ── Camera preview — top 70% ──────────────────────────────
                    ZStack(alignment: .top) {
                        CameraPreviewView(session: vm.session)
                            .frame(height: geo.size.height * 0.70)
                            .clipped()

                        // Mode toggle floated at top of camera area
                        modePicker
                            .padding(.top, safeArea.top + 10)
                    }
                    .frame(height: geo.size.height * 0.70)

                    // ── Reserved 30% ──────────────────────────────────────────
                    Spacer()
                }
            }
        }
        .onAppear  { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { vm.mode },
            set: { vm.switchMode(to: $0) }
        )) {
            ForEach(CameraMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
