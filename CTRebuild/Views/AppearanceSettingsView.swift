import SwiftUI

// MARK: - Panel Material Style
// Accessible by all panel views in this module (internal access).

enum PanelMaterialStyle: String, CaseIterable, Identifiable {
    case ultraThin  = "ultraThin"
    case thin       = "thin"
    case regular    = "regular"
    case thick      = "thick"
    case ultraThick = "ultraThick"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultraThin:  return "Ultra Thin"
        case .thin:       return "Thin"
        case .regular:    return "Regular"
        case .thick:      return "Thick"
        case .ultraThick: return "Ultra Thick"
        }
    }

    @ViewBuilder
    func background() -> some View {
        switch self {
        case .ultraThin:  Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
        case .thin:       Rectangle().fill(.thinMaterial).ignoresSafeArea()
        case .regular:    Rectangle().fill(.regularMaterial).ignoresSafeArea()
        case .thick:      Rectangle().fill(.thickMaterial).ignoresSafeArea()
        case .ultraThick: Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
        }
    }
}

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    let safeArea: EdgeInsets
    let onBack: () -> Void

    // ── Material ───────────────────────────────────────────────────────────
    @AppStorage("panel_showMaterial")   private var showMaterial    = true
    @AppStorage("panel_materialStyle")  private var materialStyleRaw = "ultraThin"

    // ── Bottom panel tint ──────────────────────────────────────────────────
    @AppStorage("panel_tintBottomR") private var bottomR: Double = 0
    @AppStorage("panel_tintBottomG") private var bottomG: Double = 0
    @AppStorage("panel_tintBottomB") private var bottomB: Double = 0
    @AppStorage("panel_tintBottomA") private var bottomA: Double = 0

    // ── Left panel tint ────────────────────────────────────────────────────
    @AppStorage("panel_tintLeftR")   private var leftR: Double = 0
    @AppStorage("panel_tintLeftG")   private var leftG: Double = 0
    @AppStorage("panel_tintLeftB")   private var leftB: Double = 0
    @AppStorage("panel_tintLeftA")   private var leftA: Double = 0

    // ── Right panel tint ───────────────────────────────────────────────────
    @AppStorage("panel_tintRightR")  private var rightR: Double = 0
    @AppStorage("panel_tintRightG")  private var rightG: Double = 0
    @AppStorage("panel_tintRightB")  private var rightB: Double = 0
    @AppStorage("panel_tintRightA")  private var rightA: Double = 0

    // ── Top panel tint ─────────────────────────────────────────────────────
    @AppStorage("panel_tintTopR")    private var topR: Double = 0
    @AppStorage("panel_tintTopG")    private var topG: Double = 0
    @AppStorage("panel_tintTopB")    private var topB: Double = 0
    @AppStorage("panel_tintTopA")    private var topA: Double = 0

    // MARK: - Computed bindings

    private var materialStyleBinding: Binding<PanelMaterialStyle> {
        Binding(
            get: { PanelMaterialStyle(rawValue: materialStyleRaw) ?? .ultraThin },
            set: { materialStyleRaw = $0.rawValue }
        )
    }

    private func colorBinding(
        r: Binding<Double>, g: Binding<Double>,
        b: Binding<Double>, a: Binding<Double>
    ) -> Binding<Color> {
        Binding(
            get: { Color(red: r.wrappedValue, green: g.wrappedValue,
                         blue: b.wrappedValue, opacity: a.wrappedValue) },
            set: { color in
                var rv: CGFloat = 0, gv: CGFloat = 0, bv: CGFloat = 0, av: CGFloat = 0
                UIColor(color).getRed(&rv, green: &gv, blue: &bv, alpha: &av)
                r.wrappedValue = Double(rv)
                g.wrappedValue = Double(gv)
                b.wrappedValue = Double(bv)
                a.wrappedValue = Double(av)
            }
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if showMaterial {
                (PanelMaterialStyle(rawValue: materialStyleRaw) ?? .ultraThin).background()
            }

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 2) {

                        // ── Material ───────────────────────────────────────
                        sectionHeader("MATERIAL")

                        VStack(spacing: 0) {
                            toggleRow(
                                icon: "square.stack.3d.up",
                                label: "Panel Material",
                                detail: "Show frosted glass on all panels",
                                binding: $showMaterial
                            )
                            if showMaterial {
                                Divider().opacity(0.1).padding(.leading, 46)
                                pickerRow(
                                    icon: "sparkles",
                                    label: "Material Style",
                                    binding: materialStyleBinding
                                )
                            }
                        }
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 14)
                        .animation(.easeInOut(duration: 0.18), value: showMaterial)

                        // ── Panel Tint ─────────────────────────────────────
                        sectionHeader("PANEL TINT")

                        Text("Overlay a color on each panel individually. Works with or without material.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)

                        tintRow(
                            icon: "rectangle.bottomthird.inset.filled",
                            label: "Bottom Panel",
                            r: $bottomR, g: $bottomG, b: $bottomB, a: $bottomA
                        )

                        tintRow(
                            icon: "sidebar.left",
                            label: "Left Panel",
                            r: $leftR, g: $leftG, b: $leftB, a: $leftA
                        )

                        tintRow(
                            icon: "sidebar.right",
                            label: "Right Panel",
                            r: $rightR, g: $rightG, b: $rightB, a: $rightA
                        )

                        tintRow(
                            icon: "rectangle.topthird.inset.filled",
                            label: "Top Panel",
                            r: $topR, g: $topG, b: $topB, a: $topA
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeArea.bottom + 24)
                }
            }
        }
    }

    // MARK: - Tint Row

    private func tintRow(
        icon: String, label: String,
        r: Binding<Double>, g: Binding<Double>,
        b: Binding<Double>, a: Binding<Double>
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
                Text(a.wrappedValue > 0.001 ? "Custom tint active" : "No tint")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(a.wrappedValue > 0.001 ? .orange.opacity(0.85) : .white.opacity(0.35))
            }

            Spacer()

            // Live swatch preview
            if a.wrappedValue > 0.001 {
                Circle()
                    .fill(Color(red: r.wrappedValue, green: g.wrappedValue,
                                blue: b.wrappedValue, opacity: a.wrappedValue))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
            }

            ColorPicker("", selection: colorBinding(r: r, g: g, b: b, a: a),
                        supportsOpacity: true)
                .labelsHidden()
                .frame(width: 32)

            // Clear button
            Button {
                r.wrappedValue = 0; g.wrappedValue = 0
                b.wrappedValue = 0; a.wrappedValue = 0
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(a.wrappedValue > 0.001 ? 0.5 : 0.15))
            }
            .buttonStyle(.plain)
            .disabled(a.wrappedValue <= 0.001)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 10)
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

            Text("APPEARANCE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(3)

            Spacer()

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

    private func toggleRow(icon: String, label: String, detail: String, binding: Binding<Bool>) -> some View {
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

    private func pickerRow(icon: String, label: String, binding: Binding<PanelMaterialStyle>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 28)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.88))

            Spacer()

            Picker("", selection: binding) {
                ForEach(PanelMaterialStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.menu)
            .tint(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
