import SwiftUI

// MARK: - Bin Grid Models

private struct SectionConfig: Identifiable {
    let id: String        // "A", "B", "S"
    let columns: Int      // positions per level
    let levels: Int = 6   // always A–F
    let columnPrefix: String   // e.g. "1A", "2A"
}

// MARK: - Left Panel View

struct LeftPanelView: View {
    let safeArea: EdgeInsets

    // Current column page: 0 = column 1, 1 = column 2, 2 = column 3
    @State private var columnPage: Int = 0
    @State private var dragOffset: CGFloat = 0

    // Which bins are occupied (placeholder — will come from server later)
    @State private var occupiedBins: Set<String> = []

    private let levelLabels = ["A", "B", "C", "D", "E", "F"]
    private let totalColumns = 3  // 1x, 2x, 3x

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────────────────────
                    Text("BIN GRID")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .tracking(4)
                        .padding(.top, safeArea.top + 16)
                        .padding(.bottom, 12)

                    // ── Swipeable grid pages ──────────────────────────────────
                    ZStack {
                        ForEach(0..<totalColumns, id: \.self) { page in
                            gridPage(page: page, geo: geo)
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

                    // ── Page dots ─────────────────────────────────────────────
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

    // MARK: - Grid Page (one column across all sections)

    @ViewBuilder
    private func gridPage(page: Int, geo: GeometryProxy) -> some View {
        let colNum = page + 1  // 1, 2, 3

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Section A — 4 positions wide
                sectionGrid(
                    colNum: colNum, sectionLetter: "A",
                    positions: 4, geo: geo
                )
                // Section B — 6 positions wide
                sectionGrid(
                    colNum: colNum, sectionLetter: "B",
                    positions: 6, geo: geo
                )
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Section Grid

    @ViewBuilder
    private func sectionGrid(
        colNum: Int,
        sectionLetter: String,
        positions: Int,
        geo: GeometryProxy
    ) -> some View {
        let columnCode = "\(colNum)\(sectionLetter)"   // e.g. "1A", "2B"
        let sidebarWidth: CGFloat = 90
        let availableWidth = geo.size.width - 16 - sidebarWidth - 6  // padding + sidebar + gap
        let cellSize = max(availableWidth / CGFloat(positions), 48)

        HStack(alignment: .top, spacing: 6) {
            // ── Bin cells grid ────────────────────────────────────────────────
            VStack(spacing: 4) {
                ForEach(levelLabels, id: \.self) { level in
                    HStack(spacing: 4) {
                        ForEach(1...positions, id: \.self) { pos in
                            let binCode = "\(columnCode)-\(pos)\(level)"
                            binCell(code: binCode, size: cellSize)
                        }
                    }
                }
            }

            // ── Right sidebar ─────────────────────────────────────────────────
            VStack(spacing: 6) {
                // Column label
                Text(columnCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: cellSize * 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                // Sales Order button
                sidebarButton(label: "Sales\nOrder")

                // Out of Stock button
                sidebarButton(label: "Out of\nStock")

                Spacer()
            }
            .frame(width: sidebarWidth)
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
                    .fill(taken
                          ? Color.white.opacity(0.04)
                          : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(taken ? 0.06 : 0.12), lineWidth: 0.5)
            )
            .onTapGesture {
                guard !taken else { return }
                // TODO: connect to server — selectBin(code)
                print("[BinGrid] selected: \(code)")
            }
    }

    // MARK: - Sidebar Button

    @ViewBuilder
    private func sidebarButton(label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
    }
}
