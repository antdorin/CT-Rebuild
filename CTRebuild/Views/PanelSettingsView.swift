import SwiftUI

// MARK: - Panel Settings View

struct PanelSettingsView: View {
    let safeArea: EdgeInsets
    let onBack: () -> Void

    // ── Auto picker mode ───────────────────────────────────────────────────
    @AppStorage("panel_autoPickerLeft")  private var autoPickerLeft  = false
    @AppStorage("panel_autoPickerRight") private var autoPickerRight = false

    // ── Behaviour ──────────────────────────────────────────────────────────
    @AppStorage("panel_hapticOnChange")  private var hapticOnChange  = false
    @AppStorage("panel_dimOnOpen")       private var dimOnOpen       = true

    // ── Left panel ─────────────────────────────────────────────────────────
    @AppStorage("panel_leftColumns")     private var leftColumns: Int = 3

    // ── Right panel ────────────────────────────────────────────────────────
    @AppStorage("panel_rightStartPage")  private var rightStartPage: Int = 0

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 2) {

                        // ── Picker Mode ───────────────────────────────────
                        sectionHeader("PICKER MODE ON OPEN")

                        VStack(spacing: 0) {
                            toggleRow(
                                icon: "sidebar.left",
                                label: "Left Panel Opens in Picker",
                                detail: "Shows the page selector immediately on swipe open",
                                binding: $autoPickerLeft
                            )
                            Divider().opacity(0.1).padding(.leading, 46)
                            toggleRow(
                                icon: "sidebar.right",
                                label: "Right Panel Opens in Picker",
                                detail: "Shows the page selector immediately on swipe open",
                                binding: $autoPickerRight
                            )
                        }
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 14)

                        // ── Behaviour ─────────────────────────────────────
                        sectionHeader("BEHAVIOUR")

                        VStack(spacing: 0) {
                            toggleRow(
                                icon: "waveform",
                                label: "Haptic on Panel Change",
                                detail: "Vibrate when a panel opens, closes, or switches",
                                binding: $hapticOnChange
                            )
                            Divider().opacity(0.1).padding(.leading, 46)
                            toggleRow(
                                icon: "circle.lefthalf.filled",
                                label: "Dim Background on Panel Open",
                                detail: "Dark overlay behind open panels",
                                binding: $dimOnOpen
                            )
                        }
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 14)

                        // ── Left Panel ────────────────────────────────────
                        sectionHeader("LEFT PANEL")

                        VStack(spacing: 0) {
                            stepperRow(
                                icon: "square.grid.3x3",
                                label: "Bin Columns",
                                detail: "Number of bin columns displayed",
                                value: $leftColumns,
                                range: 2...6
                            )
                        }
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 14)

                        // ── Right Panel ───────────────────────────────────
                        sectionHeader("RIGHT PANEL")

                        VStack(spacing: 0) {
                            stepperRow(
                                icon: "doc.on.doc",
                                label: "Default Page",
                                detail: "Which page opens first (0 = page 1)",
                                value: $rightStartPage,
                                range: 0...6
                            )
                        }
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 14)

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

            Text("PANEL SETTINGS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(3)

            Spacer()

            // Blank to balance header
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, safeArea.top + 12)
        .padding(.bottom, 12)
    }

    // MARK: - Row Helpers

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

    private func toggleRow(
        icon: String,
        label: String,
        detail: String,
        binding: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.blue.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func stepperRow(
        icon: String,
        label: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.9))
                    .frame(minWidth: 24, alignment: .center)

                Button {
                    if value.wrappedValue < range.upperBound { value.wrappedValue += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
