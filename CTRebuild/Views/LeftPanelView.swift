import SwiftUI

// MARK: - Left Panel View

struct LeftPanelView: View {
    let safeArea: EdgeInsets

    // Virtual index — can grow negative/positive without clamping (infinite)
    @State private var columnPage: Int = 0
    @State private var occupiedBins: Set<String> = []
    // true = Panel Page Picker is open; false = full-page content shown
    @State private var isPPOpen = false

    private let levelLabels = ["A", "B", "C", "D", "E", "F"]
    private let totalColumns = 3  // 1, 2, 3 — wraps infinitely

    // Real column number 1–3, wraps circularly
    private func colNum(for page: Int) -> Int {
        let m = page % totalColumns
        return m < 0 ? m + totalColumns + 1 : m + 1
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !isPPOpen {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                }

                if isPPOpen {
                    LeftWheelSelector(
                        columnPage: $columnPage,
                        isPPOpen: $isPPOpen,
                        panelSize: geo.size,
                        safeArea: safeArea,
                        totalColumns: totalColumns,
                        colNum: colNum
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    leftPageContent(geo: geo)
                        .transition(.pageTransition)
                        .onTapGesture(count: 2) {
                            withAnimation(.slideBck) {
                                isPPOpen = true
                            }
                        }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Full page content (used both in-panel and as thumbnail source)

    @ViewBuilder
    func leftPageContent(geo: GeometryProxy) -> some View {
        let headerH = safeArea.top + 42
        let dotsH   = safeArea.bottom + 26
        let pageH   = geo.size.height - headerH - dotsH
        let cellH   = (pageH - 16 - 12 - 10 * 4) / 12
        let cellW   = (geo.size.width - 16 - 5 * 4) / 6
        let cellSize = max(min(cellW, cellH), 28)
        let col     = colNum(for: columnPage)

        VStack(spacing: 0) {
            Text("BIN GRID")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .tracking(4)
                .padding(.top, safeArea.top + 16)
                .padding(.bottom, 12)

            ZStack {
                ForEach(-1...1, id: \.self) { offset in
                    let page = columnPage + offset
                    gridPage(colNum: colNum(for: page), cellSize: cellSize)
                        .frame(width: geo.size.width, height: pageH)
                        .offset(y: CGFloat(offset) * pageH)
                }
            }
            .frame(width: geo.size.width, height: pageH)
            .clipped()
            .simultaneousGesture(
                DragGesture()
                    .onEnded { value in
                        let adx = abs(value.translation.width)
                        let ady = abs(value.translation.height)
                        guard ady > adx else { return }
                        let threshold = pageH * 0.2
                        if value.translation.height < -threshold {
                            withAnimation { columnPage += 1 }
                        } else if value.translation.height > threshold {
                            withAnimation { columnPage -= 1 }
                        }
                    }
            )

            HStack(spacing: 6) {
                ForEach(0..<totalColumns, id: \.self) { i in
                    Circle()
                        .fill(col == i + 1 ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, safeArea.bottom + 12)
        }
    }

    // MARK: - Grid Page

    @ViewBuilder
    private func gridPage(colNum: Int, cellSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                sectionGrid(colNum: colNum, sectionLetter: "A", positions: 4, blankCount: 2, cellSize: cellSize)
                sectionGrid(colNum: colNum, sectionLetter: "B", positions: 6, cellSize: cellSize)
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Section Grid

    @ViewBuilder
    private func sectionGrid(colNum: Int, sectionLetter: String, positions: Int, blankCount: Int = 0, cellSize: CGFloat) -> some View {
        let columnCode = "\(colNum)\(sectionLetter)"

        VStack(spacing: 4) {
            ForEach(levelLabels, id: \.self) { level in
                HStack(spacing: 4) {
                    ForEach(1...positions, id: \.self) { pos in
                        binCell(code: "\(columnCode)-\(pos)\(level)", size: cellSize)
                    }
                    ForEach(0..<blankCount, id: \.self) { _ in
                        blankCell(size: cellSize)
                    }
                }
            }
        }
    }

    // MARK: - Blank Cell

    @ViewBuilder
    private func blankCell(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
    }

    // MARK: - Bin Cell

    @ViewBuilder
    private func binCell(code: String, size: CGFloat) -> some View {
        let taken = occupiedBins.contains(code)
        let fontSize = max(size * 0.17, 8)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6)
                .fill(taken ? Color.white.opacity(0.04) : Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(taken ? 0.06 : 0.12), lineWidth: 0.5)
            Text(code)
                .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                .foregroundColor(taken ? .white.opacity(0.25) : .white)
                .padding(.top, 5)
                .padding(.horizontal, 2)
        }
        .frame(width: size, height: size)
        .onTapGesture {
            guard !taken else { return }
            print("[BinGrid] selected: \(code)")
        }
    }
}

// MARK: - Left Wheel Selector

// MARK: - Left Panel Page Picker

private struct LeftWheelSelector: View {
    @Binding var columnPage: Int
    @Binding var isPPOpen: Bool
    let panelSize: CGSize
    let safeArea: EdgeInsets
    let totalColumns: Int
    let colNum: (Int) -> Int

    private let cardW: CGFloat = 320
    private let cardH: CGFloat = 560
    private let spacing: CGFloat = 580

    @State private var dragOffset: CGFloat = 0

    private var previewScale: CGFloat {
        guard panelSize.width > 0 else { return 1 }
        return cardW / panelSize.width
    }

    // Geo proxy substitute — compute cell sizes from panel size directly
    private func cellSize() -> CGFloat {
        let headerH = safeArea.top + 42
        let dotsH   = safeArea.bottom + 26
        let pageH   = panelSize.height - headerH - dotsH
        let cellH   = (pageH - 16 - 12 - 10 * 4) / 12
        let cellW   = (panelSize.width - 16 - 5 * 4) / 6
        return max(min(cellW, cellH), 28)
    }

    var body: some View {
        ZStack {
            ForEach((columnPage - totalColumns - 1)...(columnPage + totalColumns + 1), id: \.self) { vp in
                let col            = colNum(vp)
                let totalOffset    = CGFloat(vp - columnPage) * spacing + dragOffset
                let distCenter     = totalOffset / spacing

                leftPageSnapshot(col: col)
                    .frame(width: panelSize.width, height: panelSize.height)
                    .scaleEffect(previewScale, anchor: .center)
                    .frame(width: cardW, height: cardH)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .overlay(
                        Color.clear
                            .contentShape(RoundedRectangle(cornerRadius: 18))
                            .onTapGesture {
                                withAnimation(colNum(columnPage) == col ? .slideFwd : .spring(response: 0.3, dampingFraction: 0.85)) {
                                    if colNum(columnPage) == col { isPPOpen = false }
                                    else { columnPage = vp }
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
        .frame(width: panelSize.width, height: panelSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let dragMoves = -Int((value.translation.height / 150).rounded())
                    let velocityDelta = value.predictedEndTranslation.height - value.translation.height
                    let flickBoost: Int = velocityDelta > 250 ? -1 : velocityDelta < -250 ? 1 : 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        columnPage += dragMoves + flickBoost
                        dragOffset = 0
                    }
                }
        )
    }

    // Lightweight visual snapshot of a column page for the thumbnail
    @ViewBuilder
    private func leftPageSnapshot(col: Int) -> some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("BIN GRID")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .tracking(4)
                    .padding(.top, safeArea.top + 16)
                    .padding(.bottom, 12)
                let cs = cellSize()
                VStack(spacing: 12) {
                    sectionSnapshot(col: col, section: "A", positions: 4, blanks: 2, cs: cs)
                    sectionSnapshot(col: col, section: "B", positions: 6, blanks: 0, cs: cs)
                }
                .padding(.horizontal, 8)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(0..<totalColumns, id: \.self) { i in
                        Circle()
                            .fill(col == i + 1 ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, safeArea.bottom + 12)
            }
        }
    }

    @ViewBuilder
    private func sectionSnapshot(col: Int, section: String, positions: Int, blanks: Int, cs: CGFloat) -> some View {
        let levels = ["A","B","C","D","E","F"]
        let code   = "\(col)\(section)"
        let fs     = max(cs * 0.17, 8)
        VStack(spacing: 4) {
            ForEach(levels, id: \.self) { level in
                HStack(spacing: 4) {
                    ForEach(1...positions, id: \.self) { pos in
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            Text("\(code)-\(pos)\(level)")
                                .font(.system(size: fs, weight: .regular, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.top, 5).padding(.horizontal, 2)
                        }
                        .frame(width: cs, height: cs)
                    }
                    ForEach(0..<blanks, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.02))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.04), lineWidth: 0.5))
                            .frame(width: cs, height: cs)
                    }
                }
            }
        }
    }
}

