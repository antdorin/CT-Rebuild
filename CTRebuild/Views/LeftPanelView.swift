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
                // Cell size driven by 6-position width so A and B cells match
                let cellSize = max((geo.size.width - 16 - CGFloat(5) * 4) / 6, 44)

                VStack(spacing: 0) {
                    Text("BIN GRID")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .tracking(4)
                        .padding(.top, safeArea.top + 16)
                        .padding(.bottom, 12)

                    ZStack {
                        ForEach(0..<totalColumns, id: \.self) { page in
                            gridPage(page: page, cellSize: cellSize)
                                .frame(width: geo.size.width)
                                .offset(x: CGFloat(page - columnPage) * geo.size.width + dragOffset)
                        }
                    }
                    .frame(width: geo.size.width)
                    .clipped()
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation.width }
                            .onEnded { value in
                                let threshold = geo.size.width * 0.3
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if value.translation.width < -threshold {
                                        columnPage = min(columnPage + 1, totalColumns - 1)
                                    } else if value.translation.width > threshold {
                                        columnPage = max(columnPage - 1, 0)
                                    }
                                    dragOffset = 0
                                }
                            }
                    )

                    HStack(spacing: 6) {
                        ForEach(0..<totalColumns, id: \.self) { i in
                            Circle()
                                .fill(i == columnPage ? Color.white : Color.white.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, safeArea.bottom + 12)
                }
            }
        }
    }

    // MARK: - Grid Page

    @ViewBuilder
    private func gridPage(page: Int, cellSize: CGFloat) -> some View {
        let colNum = page + 1

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                sectionGrid(colNum: colNum, sectionLetter: "A", positions: 4, cellSize: cellSize)
                sectionGrid(colNum: colNum, sectionLetter: "B", positions: 6, cellSize: cellSize)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
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
        Text(code)
            .font(.system(size: max(size * 0.18, 8), weight: .regular, design: .monospaced))
            .foregroundColor(taken ? .white.opacity(0.25) : .white)
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

