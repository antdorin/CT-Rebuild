import SwiftUI

// MARK: - App Settings View

struct AppSettingsView: View {
    let safeArea: EdgeInsets

    @State private var showGestureSettings = false
    @State private var showHubSettings = false

    var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()

            if showGestureSettings {
                GestureSettingsView(safeArea: safeArea, onBack: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showGestureSettings = false
                    }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
            } else if showHubSettings {
                HubSettingsView(safeArea: safeArea, onBack: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showHubSettings = false
                    }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
            } else {
                settingsList
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal:   .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showGestureSettings)
        .animation(.easeInOut(duration: 0.22), value: showHubSettings)
    }

    // MARK: - Settings List

    private var settingsList: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            Text("APP SETTINGS")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .tracking(4)
                .padding(.top, safeArea.top + 16)
                .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 2) {
                    // ── Gestures ─────────────────────────────────────────
                    sectionHeader("GESTURES")

                    settingsRow(
                        icon: "hand.draw",
                        label: "Gesture Settings",
                        detail: "Configure touch gestures & thresholds"
                    ) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showGestureSettings = true
                        }
                    }

                    // ── Divider ───────────────────────────────────────────
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 10)

                    // ── Display ───────────────────────────────────────────
                    sectionHeader("DISPLAY")

                    settingsRow(icon: "moon", label: "Appearance", detail: "System (auto)") {}
                        .opacity(0.4)
                    settingsRow(icon: "textformat.size", label: "Text Size", detail: "Default") {}
                        .opacity(0.4)

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 10)

                    // ── Network ───────────────────────────────────────────
                    sectionHeader("NETWORK")

                    settingsRow(icon: "wifi", label: "Hub Connection", detail: "Manage hub URLs & connection") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showHubSettings = true
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 10)

                    // ── About ─────────────────────────────────────────────
                    sectionHeader("ABOUT")

                    settingsRow(icon: "info.circle", label: "Version", detail: "CT-Rebuild 1.0") {}
                        .opacity(0.4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, safeArea.bottom + 20)
            }
        }
    }

    // MARK: - Helpers

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

    private func settingsRow(
        icon: String,
        label: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
