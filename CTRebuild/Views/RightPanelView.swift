import SwiftUI

// MARK: - Right Panel

struct RightPanelView: View {
    let safeArea: EdgeInsets

    // true = Panel Page Picker is open; false = full-page content shown
    @State private var isPPOpen = false
    @AppStorage("rightPanelSelectedIndex") private var selectedIndex = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !isPPOpen {
                    Color.black.ignoresSafeArea()
                }

                if isPPOpen {
                    RightWheelSelector(
                        selectedIndex: $selectedIndex,
                        isPPOpen: $isPPOpen,
                        panelSize: geo.size,
                        safeArea: safeArea
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    RightPageContent(index: selectedIndex, safeArea: safeArea)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.pageTransition)
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .gestureActionFired)) { note in
            guard let raw = note.userInfo?["action"] as? String else { return }
            switch raw {
            case GestureAction.openPagePicker.rawValue:
                withAnimation(.slideBck) { isPPOpen.toggle() }
            case GestureAction.nextRightPage.rawValue:
                let total = 7
                withAnimation(.slideFwd) {
                    selectedIndex = (selectedIndex + 1) % total
                    isPPOpen = false
                }
            case GestureAction.prevRightPage.rawValue:
                let total = 7
                withAnimation(.slideBck) {
                    selectedIndex = (selectedIndex - 1 + total) % total
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

    private let shades: [Color] = [
        Color(white: 0.18), Color(white: 0.26), Color(white: 0.34),
        Color(white: 0.42), Color(white: 0.50), Color(white: 0.58),
    ]

    var body: some View {
        switch index {
        case 0:  // Page 1 — PDF Browser
            PdfBrowserView(safeArea: safeArea)
        case 6:  // Page 7 — App Settings
            AppSettingsView(safeArea: safeArea)
        default: // Pages 2–6 — placeholders
            ZStack {
                shades[index % shades.count].ignoresSafeArea()
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
    "Page 2",
    "Page 3",
    "Page 4",
    "Page 5",
    "Page 6",
    "App Settings",
]

// MARK: - Right Panel Page Picker

private struct RightWheelSelector: View {
    @Binding var selectedIndex: Int
    @Binding var isPPOpen: Bool
    let panelSize: CGSize
    let safeArea: EdgeInsets

    private let itemCount = 7
    private let cardW: CGFloat = 320
    private let spacing: CGFloat = 580

    private var cardH: CGFloat {
        guard panelSize.width > 0 else { return 560 }
        return cardW * (panelSize.height / panelSize.width)
    }

    @State private var virtualPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    private var previewScale: CGFloat {
        guard panelSize.width > 0 else { return 1 }
        return cardW / panelSize.width
    }

    /// Indices matching the current search query
    private var filteredIndices: [Int] {
        guard !searchText.isEmpty else { return [] }
        return (0..<itemCount).filter {
            rightPageTitles[$0].localizedCaseInsensitiveContains(searchText)
        }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    // Maps any virtual page to a real 0–(itemCount-1) index, wrapping circularly
    private func realIndex(_ page: Int) -> Int {
        let m = page % itemCount
        return m < 0 ? m + itemCount : m
    }

    var body: some View {
        ZStack {
            // ── Carousel (hidden while searching) ─────────────────────────
            if !isSearching {
                carousel
            }

            // ── Search bar + results overlay ──────────────────────────────
            VStack(spacing: 0) {
                searchBar
                    .padding(.top, safeArea.top + 8)
                    .padding(.horizontal, 24)

                if isSearching {
                    searchResults
                }

                Spacer()
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .onAppear {
            virtualPage = selectedIndex
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            TextField("Search pages…", text: $searchText)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .tint(.orange)
                .focused($searchFocused)
                .submitLabel(.done)
                .onSubmit {
                    if let first = filteredIndices.first {
                        selectPage(first)
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Search Results

    private var searchResults: some View {
        ScrollView {
            VStack(spacing: 4) {
                if filteredIndices.isEmpty {
                    Text("No matching pages")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 24)
                } else {
                    ForEach(filteredIndices, id: \.self) { idx in
                        Button { selectPage(idx) } label: {
                            HStack(spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange.opacity(0.85))
                                    .frame(width: 24)

                                Text(rightPageTitles[idx])
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))

                                Spacer()

                                if idx == selectedIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
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

    // MARK: - Helpers

    private func selectPage(_ index: Int) {
        searchText = ""
        searchFocused = false
        withAnimation(.slideFwd) {
            virtualPage = index
            selectedIndex = index
            isPPOpen = false
        }
    }
}
