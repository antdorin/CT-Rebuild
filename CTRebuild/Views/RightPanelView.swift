import SwiftUI

// MARK: - Right Panel

struct RightPanelView: View {
    let safeArea: EdgeInsets

    // true = Panel Page Picker is open; false = full-page content shown
    @State private var isPPOpen = false
    @AppStorage("rightPanelSelectedIndex") private var selectedIndex = 0
    @AppStorage("panel_autoPickerRight") private var autoPickerRight = false
    @AppStorage("panel_rightStartPage")  private var rightStartPage: Int = 0
    @AppStorage("panel_showMaterial")    private var showMaterial    = true
    @AppStorage("panel_materialStyle")   private var materialStyleRaw = "ultraThin"
    @AppStorage("panel_tintRightR")      private var panelTintR: Double = 0
    @AppStorage("panel_tintRightG")      private var panelTintG: Double = 0
    @AppStorage("panel_tintRightB")      private var panelTintB: Double = 0
    @AppStorage("panel_tintRightA")      private var panelTintA: Double = 0

    // ── Enabled pages ──────────────────────────────────────────────────────
    @AppStorage("panel_rightPage0_enabled") private var rightPage0Enabled = true
    @AppStorage("panel_rightPage1_enabled") private var rightPage1Enabled = true
    @AppStorage("panel_rightPage2_enabled") private var rightPage2Enabled = true
    @AppStorage("panel_rightPage3_enabled") private var rightPage3Enabled = true
    @AppStorage("panel_rightPage4_enabled") private var rightPage4Enabled = true
    @AppStorage("panel_rightPage5_enabled") private var rightPage5Enabled = true
    @AppStorage("panel_rightPage6_enabled") private var rightPage6Enabled = true
    @AppStorage("panel_rightPage7_enabled") private var rightPage7Enabled = false
    @AppStorage("panel_rightPage8_enabled") private var rightPage8Enabled = false
    @AppStorage("panel_rightPage9_enabled") private var rightPage9Enabled = false

    private var enabledIndices: [Int] {
        let flags = [rightPage0Enabled, rightPage1Enabled, rightPage2Enabled,
                     rightPage3Enabled, rightPage4Enabled, rightPage5Enabled,
                     rightPage6Enabled, rightPage7Enabled, rightPage8Enabled,
                     rightPage9Enabled]
        let result = flags.enumerated().compactMap { $1 ? $0 : nil }
        return result.isEmpty ? [0] : result
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !isPPOpen && showMaterial {
                    (PanelMaterialStyle(rawValue: materialStyleRaw) ?? .ultraThin).background()
                }
                if !isPPOpen && panelTintA > 0.001 {
                    Rectangle()
                        .fill(Color(red: panelTintR, green: panelTintG, blue: panelTintB, opacity: panelTintA))
                        .ignoresSafeArea()
                }

                if isPPOpen {
                    RightWheelSelector(
                        selectedIndex: $selectedIndex,
                        isPPOpen: $isPPOpen,
                        panelSize: geo.size,
                        safeArea: safeArea,
                        enabledIndices: enabledIndices
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    RightPageContent(index: selectedIndex, safeArea: safeArea)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if autoPickerRight { isPPOpen = true }
            else {
                let enabled = enabledIndices
                selectedIndex = enabled.contains(rightStartPage) ? rightStartPage : (enabled.first ?? 0)
            }
        }
        .onDisappear {
            isPPOpen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .gestureActionFired)) { note in
            guard let raw = note.userInfo?["action"] as? String else { return }
            switch raw {
            case GestureAction.openPagePicker.rawValue:
                withAnimation(.slideBck) { isPPOpen.toggle() }
            case GestureAction.nextRightPage.rawValue:
                let enabled = enabledIndices
                let curPos  = enabled.firstIndex(of: selectedIndex) ?? 0
                withAnimation(.slideFwd) {
                    selectedIndex = enabled[(curPos + 1) % enabled.count]
                    isPPOpen = false
                }
            case GestureAction.prevRightPage.rawValue:
                let enabled = enabledIndices
                let count   = enabled.count
                let curPos  = enabled.firstIndex(of: selectedIndex) ?? 0
                withAnimation(.slideBck) {
                    selectedIndex = enabled[(curPos - 1 + count) % count]
                    isPPOpen = false
                }
            default: break
            }
        }
    }
}

// MARK: - Right Page Content

/// Full-page content for each right-panel slot (1-indexed display).
struct RightPageContent: View {
    let index: Int
    let safeArea: EdgeInsets
    @AppStorage("panel_showMaterial") private var showMaterial = true

    private let shades: [Color] = [
        Color(white: 0.18), Color(white: 0.26), Color(white: 0.34),
        Color(white: 0.42), Color(white: 0.50), Color(white: 0.58),
    ]

    var body: some View {
        switch index {
        case 0:  // Page 1 — PDF Browser
            PdfBrowserView(safeArea: safeArea)
        case 1:  // Page 2 — Bin Locations
            BinLocationsView(safeArea: safeArea)
        case 6:  // Page 7 — App Settings
            AppSettingsView(safeArea: safeArea)
        default: // Pages 2–6 — placeholders
            ZStack {
                if showMaterial {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                }
                VStack(spacing: 16) {
                    Text("Page \(index + 1)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.top, safeArea.top)
                .padding(.bottom, safeArea.bottom)
            }
        }
    }
}

// MARK: - Page Titles

/// Human-readable names for right-panel pages (index 0–6).
private let rightPageTitles: [String] = [
    "PDF Browser",
    "Bin Locations",
    "Page 3",
    "Page 4",
    "Page 5",
    "Page 6",
    "App Settings",
    "Page 8",
    "Page 9",
    "Page 10",
]

// MARK: - Right Panel Page Picker

private struct RightWheelSelector: View {
    @Binding var selectedIndex: Int
    @Binding var isPPOpen: Bool
    let panelSize: CGSize
    let safeArea: EdgeInsets
    let enabledIndices: [Int]

    private var itemCount: Int { enabledIndices.isEmpty ? 1 : enabledIndices.count }
    private let cardW: CGFloat = 320
    private let spacing: CGFloat = 580

    private var cardH: CGFloat {
        guard panelSize.width > 0 else { return 560 }
        return cardW * (panelSize.height / panelSize.width)
    }

    @State private var virtualPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    private var previewScale: CGFloat {
        guard panelSize.width > 0 else { return 1 }
        return cardW / panelSize.width
    }

    // Maps any virtual carousel position to an actual page index via enabledIndices
    private func realIndex(_ page: Int) -> Int {
        guard !enabledIndices.isEmpty else { return 0 }
        let count = enabledIndices.count
        let m = page % count
        let pos = m < 0 ? m + count : m
        return enabledIndices[pos]
    }

    var body: some View {
        carousel
            .frame(width: panelSize.width, height: panelSize.height)
            .onAppear {
                // Start carousel centered on the enabled position of selectedIndex
                if let pos = enabledIndices.firstIndex(of: selectedIndex) {
                    virtualPage = pos
                } else {
                    virtualPage = 0
                }
            }
    }

    // MARK: - Carousel

    private var carousel: some View {
        ZStack {
            ForEach((virtualPage - 2)...(virtualPage + 2), id: \.self) { vp in
                let real           = realIndex(vp)
                let totalOffset    = CGFloat(vp - virtualPage) * spacing + dragOffset
                let distCenter     = totalOffset / spacing

                ZStack(alignment: .bottom) {
                    RightPageContent(index: real, safeArea: safeArea)
                        .frame(width: panelSize.width, height: panelSize.height)
                        .scaleEffect(previewScale, anchor: .center)
                        .frame(width: cardW, height: cardH)
                        .clipped()

                    // Page label overlay
                    Text(rightPageTitles[real])
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                .overlay(
                    Color.clear
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                        .onTapGesture {
                            withAnimation(realIndex(virtualPage) == real ? .slideFwd : .spring(response: 0.3, dampingFraction: 0.85)) {
                                if realIndex(virtualPage) == real {
                                    isPPOpen = false
                                } else {
                                    virtualPage = vp
                                    selectedIndex = real
                                }
                            }
                        }
                )
                .offset(y: totalOffset)
                .rotation3DEffect(
                    .degrees(Double(distCenter) * -35),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.5
                )
                .scaleEffect(1.0 - abs(distCenter) * 0.15)
                .opacity(1.0 - abs(distCenter) * 0.4)
                .zIndex(1.0 - abs(distCenter) * 0.5)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let dragMoves = -Int((value.translation.height / 550).rounded())
                    let velocityDelta = value.predictedEndTranslation.height - value.translation.height
                    let flickBoost: Int = velocityDelta > 250 ? -1 : velocityDelta < -250 ? 1 : 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        virtualPage += dragMoves + flickBoost
                        selectedIndex = realIndex(virtualPage)
                        dragOffset = 0
                    }
                }
        )
    }

}

// MARK: - Bin Locations View

struct BinLocationsView: View {
    let safeArea: EdgeInsets
    @ObservedObject private var binStore = BinDataStore.shared
    @AppStorage("panel_showMaterial") private var showMaterial = true

    var body: some View {
        ZStack {
            if showMaterial {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                // Header
                Text("BIN LOCATIONS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(4)
                    .padding(.top, safeArea.top + 16)
                    .padding(.bottom, 12)

                Divider().opacity(0.12)

                let entries = binStore.binQuantities.sorted { $0.key < $1.key }

                if entries.isEmpty {
                    Spacer()
                    Text("NO ACTIVE PDF")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .tracking(3)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(entries, id: \.key) { bin, qty in
                                HStack(spacing: 0) {
                                    Text(bin)
                                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer()
                                    Text("\(qty)")
                                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                Divider().opacity(0.1).padding(.horizontal, 20)
                            }
                        }
                        .padding(.bottom, safeArea.bottom + 16)
                    }
                }
            }
        }
    }
}
