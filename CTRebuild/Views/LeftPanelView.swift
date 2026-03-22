import SwiftUI

// MARK: - Left Panel View

struct LeftPanelView: View {
    let safeArea: EdgeInsets

    @State private var columnPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var occupiedBins: Set<String> = []

    private let levelLabels = ["A", "B", "C", "D", "E", "F"]
    private let totalColumns = 3

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            GeometryReader { geo in
                // B has 6 cells + 5 gaps, A has 4 cells + 3 gaps, 1 gap between sections, 16pt H padding
                // Total: 10 cells + (5+3+1)×4 + 16 = 10c + 52
                let cellSize = max((geo.size.width - 52) / 10, 30)
                let headerHeight: CGFloat = safeArea.top + 44
                let dotsHeight: CGFloat = safeArea.bottom + 32
                let pageHeight = geo.size.height - headerHeight - dotsHeight

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────────────────────
                    Text("BIN GRID")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .tracking(4)
                        .frame(height: headerHeight, alignment: .bottom)
                        .padding(.bottom, 8)

                    // ── Vertical infinite paged grid ──────────────────────────
                    ZStack {
                        ForEach([-1, 0, 1], id: \.self) { offset in
                            let page = ((columnPage + offset) % totalColumns + totalColumns) % totalColumns
                            gridPage(page: page, cellSize: cellSize)
                                .frame(width: geo.size.width, height: pageHeight)
                                .offset(y: CGFloat(offset) * pageHeight + dragOffset)
                        }
                    }
                    .frame(width: geo.size.width, height: pageHeight)
                    .clipped()
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation.height }
                            .onEnded { value in
                                let threshold = pageHeight * 0.25
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if value.translation.height < -threshold {
                                        columnPage = (columnPage + 1) % totalColumns
                                    } else if value.translation.height > threshold {
                                        columnPage = ((columnPage - 1) % totalColumns + totalColumns) % totalColumns
                                    }
                                    dragOffset = 0
                                }
                            }
                    )

                    // ── Page dots ─────────────────────────────────────────────
                    HStack(spacing: 6) {
                        ForEach(0..<totalColumns, id: \.self) { i in
                            Circle()
                                .fill(i == columnPage ? Color.white : Color.white.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(height: dotsHeight, alignment: .top)
                    .padding(.top, 10)
                }
            }
        }
    }

    // MARK: - Grid Page
    // B section (6 wide) on the left, A section (4 wide) on the right

    @ViewBuilder
    private func gridPage(page: Int, cellSize: CGFloat) -> some View {
        let colNum = page + 1

        HStack(alignment: .top, spacing: 4) {
            sectionGrid(colNum: colNum, sectionLetter: "B", positions: 6, cellSize: cellSize)
            sectionGrid(colNum: colNum, sectionLetter: "A", positions: 4, cellSize: cellSize)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
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
        VStack(alignment: .leading, spacing: 0) {
            Text(code)
                .font(.system(size: max(size * 0.16, 7), weight: .regular, design: .monospaced))
                .foregroundColor(taken ? .white.opacity(0.2) : .white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 3)
                .padding(.leading, 3)
            Spacer()
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(taken ? Color.white.opacity(0.04) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(taken ? 0.06 : 0.12), lineWidth: 0.5)
        )
        .onTapGesture {
            guard !taken else { return }
            print("[BinGrid] selected: \(code)")
        }
    }
}

