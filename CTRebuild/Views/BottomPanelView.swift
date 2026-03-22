import SwiftUI
import AVFoundation

struct BottomPanelView: View {
    let safeArea: EdgeInsets

    @State private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            // ── Translucent background ────────────────────────────────────────
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {

                    // ── Camera feed — top 70% ─────────────────────────────────
                    ZStack {
                        Color.black   // letterbox fill behind camera feed

                        switch viewModel.permission {
                        case .authorized:
                            CameraPreviewView(session: viewModel.session)
                        case .denied:
                            deniedView
                        case .undetermined:
                            // Spinner while waiting for the dialog
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(height: geo.size.height * 0.70)
                    .clipped()

                    // ── Results area — bottom 30% ─────────────────────────────
                    VStack(spacing: 6) {
                        if let scan = viewModel.lastScan {
                            Text(scan.value)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                            Text(scan.symbology.rawValue)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("AWAITING SCAN")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                                .tracking(4)
                        }
                    }
                    .frame(height: geo.size.height * 0.30)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
            }
        }
        .onAppear {
            viewModel.requestPermission()
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }

    // MARK: - Denied State

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.5))
            Text("Camera access required")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.white)
        }
    }
}
