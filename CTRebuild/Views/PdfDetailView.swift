import SwiftUI

// MARK: - PDF Detail View (server-rendered images)
// Shared viewer used by both PdfBrowserView and the camera overlay's active-PDF sheet.

struct PdfDetailView: View {
    let title: String
    let safeArea: EdgeInsets
    let filenames: [String]
    let pageCounts: [Int]
    @Binding var currentPage: Int
    let onBack: () -> Void

    @State private var pageImages: [Int: UIImage] = [:]
    @State private var loadingPages: Set<Int> = []
    @State private var isPicked: Bool = false
    @State private var isShipped: Bool = false
    @AppStorage("panel_showMaterial") private var showMaterial = true

    private var totalPages: Int { pageCounts.reduce(0, +) }

    /// Maps a global page index to (filename, page-within-file).
    private func pageMapping(_ globalIndex: Int) -> (String, Int)? {
        var offset = 0
        for (i, count) in pageCounts.enumerated() {
            if globalIndex < offset + count {
                return (filenames[i], globalIndex - offset)
            }
            offset += count
        }
        return nil
    }

    var body: some View {
        ZStack {
            if showMaterial {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }
            VStack(spacing: 0) {

                // ── Title bar ─────────────────────────────────────────────
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 16)
                    .padding(.top, safeArea.top + 8)
                    .padding(.bottom, 8)

                Divider().opacity(0.12)

                // ── Content – swipeable image pages ───────────────────────
                TabView(selection: $currentPage) {
                    ForEach(0..<totalPages, id: \.self) { pageIdx in
                        pageView(for: pageIdx)
                            .tag(pageIdx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Color.black)

                Divider().opacity(0.12)

                // ── Bottom bar ─────────────────────────────────────────────
                HStack(spacing: 0) {

                    // Back button (left)
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    Divider().frame(height: 20).opacity(0.2)

                    // Page counter
                    Text("\(currentPage + 1) / \(totalPages)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 8)

                    Divider().frame(height: 20).opacity(0.2)

                    statusToggle(label: "PICKED", active: isPicked, activeColor: .orange) {
                        isPicked.toggle()
                        UserDefaults.standard.set(isPicked, forKey: "docpicked:\(title)")
                    }

                    statusToggle(label: "SHIPPED", active: isShipped, activeColor: .green) {
                        isShipped.toggle()
                        UserDefaults.standard.set(isShipped, forKey: "docshipped:\(title)")
                    }

                    Divider().frame(height: 20).opacity(0.2)

                    Spacer()
                }
                .background(Color.white.opacity(0.05))
                .padding(.bottom, safeArea.bottom)
            }
        }
        .onAppear {
            isPicked  = UserDefaults.standard.bool(forKey: "docpicked:\(title)")
            isShipped = UserDefaults.standard.bool(forKey: "docshipped:\(title)")
        }
        .onChange(of: currentPage) { _ in prefetchNearby(currentPage) }
        .task { prefetchNearby(currentPage) }
    }

    // MARK: - Page image view

    @ViewBuilder
    private func pageView(for idx: Int) -> some View {
        if let image = pageImages[idx] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                Color.black
                ProgressView().tint(.white)
            }
            .task { await loadPage(idx) }
        }
    }

    private func loadPage(_ idx: Int) async {
        guard pageImages[idx] == nil, !loadingPages.contains(idx) else { return }
        loadingPages.insert(idx)
        defer { loadingPages.remove(idx) }
        guard let (filename, pageInFile) = pageMapping(idx) else { return }
        do {
            let image = try await HubClient.shared.fetchPdfPageImage(filename: filename, page: pageInFile)
            pageImages[idx] = image
        } catch {
            // User can swipe away and back to retry
        }
    }

    private func prefetchNearby(_ page: Int) {
        for offset in -1...1 {
            let idx = page + offset
            guard idx >= 0, idx < totalPages, pageImages[idx] == nil else { continue }
            Task { await loadPage(idx) }
        }
    }

    private func statusToggle(label: String, active: Bool, activeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? activeColor : .white.opacity(0.45))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(active ? activeColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 2).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
