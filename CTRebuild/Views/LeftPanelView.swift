import SwiftUI

// MARK: - Left Panel View

struct LeftPanelView: View {
    let safeArea: EdgeInsets

    // Virtual index — can grow negative/positive without clamping (infinite)
    @State private var columnPage: Int = 0
    @State private var occupiedBins: Set<String> = []

    private let levelLabels = ["A", "B", "C", "D", "E", "F"]
    private let totalColumns = 3  // 1, 2, 3 — wraps infinitely

    // Real column number 1–3, wraps circularly
    private func colNum(for page: Int) -> Int {
        let m = page % totalColumns
        return m < 0 ? m + totalColumns + 1 : m + 1
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            GeometryReader { geo in
                // ── Cell size: constrained by both width (6 cols) and height (12 rows) ──
                // Header: safeTop + 16 top pad + ~14 text + 12 bottom pad = safeTop + 42
                // Dots:   8 top pad + 6 dot + 12 bottom pad + safeBottom = 26 + safeBottom
                let headerH = safeArea.top + 42
                let dotsH   = safeArea.bottom + 26
                let pageH   = geo.size.height - headerH - dotsH
                // 12 rows, 10 row-gaps of 4pt, 12pt section gap, 16pt page vertical padding
                let cellH = (pageH - 16 - 12 - 10 * 4) / 12
                // 6 columns, 5 col-gaps of 4pt, 16pt page horizontal padding
                let cellW = (geo.size.width - 16 - 5 * 4) / 6
                let cellSize = max(min(cellW, cellH), 28)

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────────────────────
                    Text("BIN GRID")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .tracking(4)
                        .padding(.top, safeArea.top + 16)
                        .padding(.bottom, 12)

                    // ── Vertical swipeable pages ──────────────────────────────
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
                                let threshold = pageH * 0.2
                                if value.translation.height < -threshold {
                                    columnPage += 1
                                } else if value.translation.height > threshold {
                                    columnPage -= 1
                                }
                            }
                    )

                    // ── Page indicator ────────────────────────────────────────
                    HStack(spacing: 6) {
                        ForEach(0..<totalColumns, id: \.self) { i in
                            Circle()
                                .fill(colNum(for: columnPage) == i + 1
                                      ? Color.white
                                      : Color.white.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, safeArea.bottom + 12)
                }
            }
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

