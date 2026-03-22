import SwiftUI
import VisionKit
import AVFoundation

struct BottomPanelView: View {
    let safeArea: EdgeInsets

    @State private var mode: CameraMode = .scan
    @State private var isScanning = false
    @State private var cameraAuthorized = false

    var body: some View {
        ZStack(alignment: .top) {
            // ── Translucent background — full bleed ───────────────────────────
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // ── Camera area — top 70% ─────────────────────────────────
                    ZStack(alignment: .top) {
                        if cameraAuthorized && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                            DataScannerView(
                                isScanning: isScanning && mode == .scan,
                                onScan: { _ in
                                    // TODO: forward scanned value to WarehouseAPIService
                                }
                            )
                            .frame(height: geo.size.height * 0.70)
                            .clipped()
                        } else {
                            // Simulator fallback — plain dark rect
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .frame(height: geo.size.height * 0.70)
                                .overlay(
                                    Text("Camera unavailable")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                )
                        }

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
        .onAppear  { requestCameraAccess() }
        .onDisappear { isScanning = false }
    }

    // MARK: - Camera Permission

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            isScanning = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                    isScanning = granted
                }
            }
        default:
            cameraAuthorized = false
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(CameraMode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
