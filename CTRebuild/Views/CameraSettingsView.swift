import SwiftUI
import AVFoundation

// MARK: - Camera Settings View

struct CameraSettingsView: View {
    let safeArea: EdgeInsets
    let onBack: () -> Void

    // Persisted camera settings
    @AppStorage("cam_torchEnabled") private var torchEnabled = false
    @AppStorage("cam_autoFocusEnabled") private var autoFocusEnabled = true
    @AppStorage("cam_continuousAutoFocus") private var continuousAutoFocus = true
    @AppStorage("cam_autoExposure") private var autoExposure = true
    @AppStorage("cam_highResCapture") private var highResCapture = false
    @AppStorage("cam_defaultZoom") private var defaultZoom: Double = 1.0
    @AppStorage("cam_scanRegionEnabled") private var scanRegionEnabled = false
    @AppStorage("cam_hapticOnScan") private var hapticOnScan = true
    @AppStorage("cam_arkitEnabled") private var arkitEnabled = false
    @AppStorage("cam_coremlEnabled") private var coremlEnabled = false
    @AppStorage("cam_dragZoomSensitivity") private var dragZoomSensitivity: Double = 80
    @AppStorage("cam_maxZoomLevel") private var maxZoomLevel: Double = 10
    @AppStorage("panel_showMaterial") private var showMaterial = true

    var body: some View {
        ZStack {
            if showMaterial {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 2) {
                        // ── Lighting ──────────────────────────────────────
                        sectionHeader("LIGHTING")

                        toggleRow(icon: "flashlight.on.fill",
                                  label: "Torch / Flashlight",
                                  detail: "Keep torch on while scanning",
                                  isOn: $torchEnabled)

                        toggleRow(icon: "camera.metering.spot",
                                  label: "Auto Exposure",
                                  detail: "Automatically adjust brightness",
                                  isOn: $autoExposure)

                        divider

                        // ── Focus ─────────────────────────────────────────
                        sectionHeader("FOCUS")

                        toggleRow(icon: "camera.viewfinder",
                                  label: "Auto Focus",
                                  detail: "Automatically focus on barcodes",
                                  isOn: $autoFocusEnabled)

                        toggleRow(icon: "scope",
                                  label: "Continuous Auto Focus",
                                  detail: "Continuously re-focus as camera moves",
                                  isOn: $continuousAutoFocus)

                        divider

                        // ── Zoom & Resolution ─────────────────────────────
                        sectionHeader("ZOOM & RESOLUTION")

                        sliderRow(icon: "plus.magnifyingglass",
                                  label: "Default Zoom",
                                  value: $defaultZoom,
                                  range: 1.0...5.0,
                                  step: 0.5,
                                  format: "%.1f×")

                        toggleRow(icon: "camera.aperture",
                                  label: "High-Res Capture",
                                  detail: "Use maximum resolution (uses more battery)",
                                  isOn: $highResCapture)

                        divider

                        // ── Detection ─────────────────────────────────────
                        sectionHeader("DETECTION")

                        toggleRow(icon: "viewfinder",
                                  label: "Restrict Scan Region",
                                  detail: "Only detect barcodes in center area",
                                  isOn: $scanRegionEnabled)

                        toggleRow(icon: "iphone.radiowaves.left.and.right",
                                  label: "Haptic on Scan",
                                  detail: "Vibrate when a barcode is detected",
                                  isOn: $hapticOnScan)

                        divider

                        // ── Frameworks ──────────────────────────────────────
                        sectionHeader("FRAMEWORKS")

                        toggleRow(icon: "arkit",
                                  label: "ARKit",
                                  detail: "Spatial tracking & depth sensing",
                                  isOn: $arkitEnabled)

                        toggleRow(icon: "brain",
                                  label: "Core ML",
                                  detail: "On-device machine learning models",
                                  isOn: $coremlEnabled)

                        divider

                        // ── Drag Zoom ───────────────────────────────────────
                        sectionHeader("DRAG ZOOM")

                        sliderRow(icon: "hand.draw",
                                  label: "Sensitivity",
                                  value: $dragZoomSensitivity,
                                  range: 30...200,
                                  step: 10,
                                  format: "%.0f pt")

                        sliderRow(icon: "arrow.up.left.and.arrow.down.right",
                                  label: "Max Zoom",
                                  value: $maxZoomLevel,
                                  range: 2...20,
                                  step: 1,
                                  format: "%.0f×")

                        divider

                        // ── Reset ─────────────────────────────────────────
                        Button(action: resetDefaults) {
                            HStack {
                                Spacer()
                                Text("Reset to Defaults")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.orange.opacity(0.85))
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeArea.bottom + 24)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("CAMERA SETTINGS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(3)

            Spacer()

            // Invisible balance so title stays centered
            Text("Settings")
                .font(.system(size: 13))
                .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.top, safeArea.top + 12)
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private var divider: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.vertical, 10)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .tracking(3)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func toggleRow(icon: String, label: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sliderRow(icon: String, label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 28)

                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.85))
            }

            Slider(value: value, in: range, step: step)
                .tint(.orange)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Reset

    private func resetDefaults() {
        torchEnabled = false
        autoFocusEnabled = true
        continuousAutoFocus = true
        autoExposure = true
        highResCapture = false
        defaultZoom = 1.0
        scanRegionEnabled = false
        hapticOnScan = true
        arkitEnabled = false
        coremlEnabled = false
        dragZoomSensitivity = 80
        maxZoomLevel = 10
    }
}
