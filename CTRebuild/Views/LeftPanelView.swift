import SwiftUI

// MARK: - Left Panel View

struct LeftPanelView: View {
    let safeArea: EdgeInsets

    // Virtual index — can grow negative/positive without clamping (infinite)
    @State private var columnPage: Int = 0
    @State private var dragOffset: CGFloat = 0
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
                let cellSize = max((geo.size.width - 16 - CGFloat(5) * 4) / 6, 44)

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────────────────────
                    Text("BIN GRID")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .tracking(4)
                        .padding(.top, safeArea.top + 16)
                        .padding(.bottom, 12)

                    // ── Vertical swipeable pages ──────────────────────────────
                    // Render prev, current, next so transitions are seamless
                    ZStack {
                        ForEach(-1...1, id: \.self) { offset in
                            let page = columnPage + offset
                            gridPage(colNum: colNum(for: page), cellSize: cellSize)
                                .frame(width: geo.size.width, height: geo.size.height * 0.88)
                                .offset(y: CGFloat(offset) * (geo.size.height * 0.88) + dragOffset)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height * 0.88)
                    .clipped()
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation.height }
                            .onEnded { value in
                                let threshold = geo.size.height * 0.2
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    if value.translation.height < -threshold {
                                        columnPage += 1
                                    } else if value.translation.height > threshold {
                                        columnPage -= 1
                                    }
                                    dragOffset = 0
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
        VStack(spacing: 12) {
            sectionGrid(colNum: colNum, sectionLetter: "A", positions: 4, cellSize: cellSize)
            sectionGrid(colNum: colNum, sectionLetter: "B", positions: 6, cellSize: cellSize)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Section Grid

    @ViewBuilder
    private func sectionGrid(colNum: Int, sectionLetter: String, positions: Int, cellSize: CGFloat) -> some View {
        let columnCode = "\(colNum)\(sectionLetter)"

        VStack(spacing: 4) {
            ForEach(levelLabels, id: \.self) { level in
                HStack(spacing: 4) {
                    ForEach(1...positions, id: \.self) { pos in
                        binCell(code: "\(columnCode)-\(pos)\(level)", size: cellSize)
                    }
                }
            }
        }
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

