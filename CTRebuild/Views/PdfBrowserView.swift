import SwiftUI
import PDFKit
import Vision

// MARK: - SO Number Helpers

private let soRegex = try! NSRegularExpression(pattern: #"SO-[A-Za-z0-9]+-[A-Za-z0-9]+"#)

private func extractSOs(from text: String) -> [String] {
    let ns = text as NSString
    return soRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range) }
}

/// Returns "SO-01-0001" for one match or "SO-01-0001 – SO-01-0024" for many.
private func soDisplayTitle(from doc: PDFDocument) -> String {
    var seen = Set<String>(); var ordered: [String] = []
    for i in 0..<doc.pageCount {
        for so in extractSOs(from: doc.page(at: i)?.string ?? "") {
            if seen.insert(so).inserted { ordered.append(so) }
        }
    }
    if ordered.isEmpty { return "" }
    if ordered.count == 1 { return ordered[0] }
    return "\(ordered.first!) – \(ordered.last!)"
}

// MARK: - Date Extraction from filename (fallback when server provides no modified date)

private func extractDate(from filename: String) -> Date? {
    let name = (filename as NSString).deletingPathExtension
    let cal = Calendar.current
    func d(y: Int, m: Int, day: Int) -> Date? {
        cal.date(from: DateComponents(year: y, month: m, day: day))
    }
    // ISO: 2024-01-15
    let re1 = try! NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})"#)
    if let m = re1.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
        let ns = name as NSString
        if let y = Int(ns.substring(with: m.range(at: 1))),
           let mo = Int(ns.substring(with: m.range(at: 2))),
           let da = Int(ns.substring(with: m.range(at: 3))) { return d(y: y, m: mo, day: da) }
    }
    // US: 01-15-2024
    let re2 = try! NSRegularExpression(pattern: #"(\d{2})-(\d{2})-(\d{4})"#)
    if let m = re2.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
        let ns = name as NSString
        if let mo = Int(ns.substring(with: m.range(at: 1))),
           let da = Int(ns.substring(with: m.range(at: 2))),
           let y  = Int(ns.substring(with: m.range(at: 3))) { return d(y: y, m: mo, day: da) }
    }
    // Compact: 20240115
    let re3 = try! NSRegularExpression(pattern: #"(\d{4})(\d{2})(\d{2})"#)
    if let m = re3.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
        let ns = name as NSString
        if let y  = Int(ns.substring(with: m.range(at: 1))),
           let mo = Int(ns.substring(with: m.range(at: 2))),
           let da = Int(ns.substring(with: m.range(at: 3))) { return d(y: y, m: mo, day: da) }
    }
    return nil
}

// MARK: - Date Group Model

struct PdfDateGroup: Identifiable, Equatable {
    let id: String
    let dateLabel: String   // e.g. "January 15, 2024"
    let soLabel: String     // e.g. "SO-01-0001 – SO-01-0024" (from filenames)
    let sortDate: Date
    let filenames: [String]
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

private func groupFiles(_ metas: [PdfMeta]) -> [PdfDateGroup] {
    var byKey: [String: (Date, [PdfMeta])] = [:]
    let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .none
    let iso1 = ISO8601DateFormatter()
    iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let iso2 = ISO8601DateFormatter()
    iso2.formatOptions = [.withInternetDateTime]

    for meta in metas {
        var date: Date?
        if !meta.modified.isEmpty {
            date = iso1.date(from: meta.modified) ?? iso2.date(from: meta.modified)
        }
        if date == nil { date = extractDate(from: meta.name) }

        if let date {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
            if byKey[key] == nil { byKey[key] = (date, []) }
            byKey[key]!.1.append(meta)
        } else {
            byKey["z_\(meta.name)"] = (Date.distantPast, [meta])
        }
    }

    return byKey
        .map { key, v -> PdfDateGroup in
            let filenames = v.1.map { $0.name }.sorted()
            let allSOs = filenames.flatMap { extractSOs(from: $0) }
            var seen = Set<String>(); var orderedSOs: [String] = []
            for so in allSOs { if seen.insert(so).inserted { orderedSOs.append(so) } }
            let soLabel: String
            switch orderedSOs.count {
            case 0:  soLabel = ""
            case 1:  soLabel = orderedSOs[0]
            default: soLabel = "\(orderedSOs.first!) \u{2013} \(orderedSOs.last!)"
            }
            return PdfDateGroup(id: key,
                                dateLabel: v.0 == .distantPast ? "No Date" : df.string(from: v.0),
                                soLabel: soLabel,
                                sortDate: v.0,
                                filenames: filenames)
        }
        .sorted { $0.sortDate > $1.sortDate }
}

private func mergePDFs(from parts: [Data]) -> PDFDocument {
    let out = PDFDocument()
    var idx = 0
    for data in parts {
        guard let doc = PDFDocument(data: data) else { continue }
        for p in 0..<doc.pageCount {
            if let page = doc.page(at: p), let copy = page.copy() as? PDFPage {
                out.insert(copy, at: idx); idx += 1
            }
        }
    }
    return out
}

// MARK: - Sort Field

enum PdfSortField: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case soNumber       = "SO Number"
    case item           = "Item"
    case terms          = "Terms"
    case shippingMethod = "Shipping Method"
    case companyName    = "Company Name"
    case binLocation    = "Bin Location"

    var systemImage: String {
        switch self {
        case .soNumber:       return "number"
        case .item:           return "archivebox"
        case .terms:          return "doc.text"
        case .shippingMethod: return "shippingbox"
        case .companyName:    return "building.2"
        case .binLocation:    return "location"
        }
    }

    func extractKey(from text: String) -> String {
        switch self {
        case .soNumber:
            return extractSOs(from: text).first ?? "~~~"
        case .item:
            return capture(text, #"(?:Item(?:\s+Number?)?|Part(?:\s+No\.?))[\s:]+([^\n]+)"#) ?? "~~~"
        case .terms:
            return capture(text, #"(?:Terms?|Payment\s+Terms?)[\s:]+([^\n]+)"#) ?? "~~~"
        case .shippingMethod:
            return capture(text, #"(?:Ship(?:ping)?\s*(?:Method|Via|By|Mode)?)[\s:]+([^\n]+)"#) ?? "~~~"
        case .companyName:
            if let c = capture(text, #"(?:Company|Customer|Bill\s+To|Ship\s+To)[\s:]+([^\n]+)"#) { return c }
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? "~~~"
        case .binLocation:
            return capture(text, #"(?:Bin(?:\s+Location?)?|Location)[\s:]+([^\n]+)"#) ?? "~~~"
        }
    }

    private func capture(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m  = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r  = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespaces)
    }
}

private func sortedDoc(_ doc: PDFDocument, by field: PdfSortField) -> PDFDocument {
    let pages: [(PDFPage, String)] = (0..<doc.pageCount).compactMap { i in
        guard let p = doc.page(at: i) else { return nil }
        return (p, field.extractKey(from: p.string ?? ""))
    }
    let sorted = pages.sorted { $0.1 < $1.1 }
    let out = PDFDocument()
    for (i, (page, _)) in sorted.enumerated() {
        if let copy = page.copy() as? PDFPage {
            out.insert(copy, at: i)
        }
    }
    return out
}

// MARK: - PDF Browser View

struct PdfBrowserView: View {
    let safeArea: EdgeInsets

    @State private var groups: [PdfDateGroup] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    // open group state
    @State private var openedGroup: PdfDateGroup? = nil
    @State private var mergedDoc: PDFDocument? = nil
    @State private var isLoadingGroup = false
    @State private var groupError: String? = nil

    // per-group last-page memory (group.id → page index)
    @State private var lastPages: [String: Int] = [:]

    // per-group cached merged PDFDocuments (for bin extraction without re-download)
    @State private var cachedDocs: [String: PDFDocument] = [:]

    @ObservedObject private var binStore = BinDataStore.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let group = openedGroup, let doc = mergedDoc {
                PdfDetailView(
                    document: doc,
                    title: group.soLabel.isEmpty ? group.dateLabel : group.soLabel,
                    safeArea: safeArea,
                    currentPage: Binding(
                        get: { lastPages[group.id] ?? 0 },
                        set: { lastPages[group.id] = $0 }
                    ),
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            openedGroup = nil
                            mergedDoc = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
            } else {
                fileListContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal:   .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: openedGroup != nil)
        .task { await loadFiles() }
    }

    // MARK: - File List

    @ViewBuilder
    private var fileListContent: some View {
        VStack(spacing: 0) {
            Text("PDF VIEWER")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .tracking(4)
                .padding(.top, safeArea.top + 16)
                .padding(.bottom, 12)

            if isLoading {
                Spacer(); ProgressView().tint(.white); Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36)).foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Button("Retry") { Task { await loadFiles() } }
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            } else if groups.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "doc.fill").font(.system(size: 36)).foregroundColor(.white.opacity(0.2))
                    Text("No PDFs found").font(.system(size: 13, design: .monospaced)).foregroundColor(.secondary)
                    Text("Select a folder in CT-Hub").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary.opacity(0.6))
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(groups) { group in
                            groupRow(group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, safeArea.bottom + 16)
                }
            }
        }
        .overlay {
            if isLoadingGroup {
                ZStack {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Merging PDFs\u{2026}")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private func groupRow(_ group: PdfDateGroup) -> some View {
        let isActive = binStore.isActive(groupId: group.id)

        return HStack(spacing: 0) {
            // ── Toggle button (left edge) ─────────────────────────────────
            Button {
                Task { await toggleGroupActive(group) }
            } label: {
                Circle()
                    .fill(isActive ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // ── Main row (opens PDF viewer) ───────────────────────────────
            Button { Task { await openGroup(group) } } label: {
                HStack(spacing: 14) {
                    Image(systemName: group.filenames.count > 1 ? "doc.on.doc" : "doc")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        // Date label
                        Text(group.dateLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        // Per-file SO labels
                        ForEach(group.filenames, id: \.self) { filename in
                            let so = extractSOs(from: filename).first ?? filename
                            Text(so)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }

                    Spacer()

                    // Bookmark badge if we have a saved position
                    if let page = lastPages[group.id], page > 0 {
                        Text("p.\(page + 1)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue.opacity(0.8))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.2))
                }
                .padding(.trailing, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func loadFiles() async {
        isLoading = true; errorMessage = nil
        do {
            // Try metadata endpoint first (provides real modification dates).
            // Fall back to filename-only list for older server versions.
            let metas: [PdfMeta]
            do {
                metas = try await HubClient.shared.fetchPdfMeta()
            } catch {
                let names = try await HubClient.shared.fetchPdfList()
                metas = names.map { PdfMeta(name: $0, modified: "") }
            }
            groups = groupFiles(metas)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openGroup(_ group: PdfDateGroup) async {
        isLoadingGroup = true; groupError = nil
        do {
            let doc = try await downloadAndMerge(group)
            withAnimation(.easeInOut(duration: 0.22)) {
                mergedDoc = doc
                openedGroup = group
            }
        } catch {
            groupError = error.localizedDescription
        }
        isLoadingGroup = false
    }

    private func toggleGroupActive(_ group: PdfDateGroup) async {
        if binStore.isActive(groupId: group.id) {
            binStore.deactivate(groupId: group.id)
            cachedDocs.removeValue(forKey: group.id)
        } else {
            // Download + merge if not already cached
            do {
                let doc = try await downloadAndMerge(group)
                binStore.activate(groupId: group.id, document: doc)
            } catch {
                // Silently skip on network error (user can retry)
            }
        }
    }

    /// Downloads all PDFs for a group and returns the merged document (caches result).
    private func downloadAndMerge(_ group: PdfDateGroup) async throws -> PDFDocument {
        if let cached = cachedDocs[group.id] { return cached }
        var parts: [Data] = []
        for filename in group.filenames {
            parts.append(try await HubClient.shared.fetchPdf(filename: filename))
        }
        let doc = mergePDFs(from: parts)
        cachedDocs[group.id] = doc
        return doc
    }
}

// MARK: - PDF Detail View

private struct PdfDetailView: View {
    let document: PDFDocument
    let title: String
    let safeArea: EdgeInsets
    @Binding var currentPage: Int
    let onBack: () -> Void

    @State private var showTextMode = false
    @State private var showSortSheet = false
    @State private var displayDoc: PDFDocument
    @State private var soTitle: String = ""
    @State private var singlePageMode = false
    @State private var scaleFactor: CGFloat = 1.0
    @State private var showOcrMode = false

    init(document: PDFDocument, title: String, safeArea: EdgeInsets,
         currentPage: Binding<Int>, onBack: @escaping () -> Void) {
        self.document    = document
        self.title       = title
        self.safeArea    = safeArea
        self._currentPage = currentPage
        self.onBack      = onBack
        self._displayDoc = State(initialValue: document)
    }

    private var extractedText: String {
        var parts: [String] = []
        for i in 0..<displayDoc.pageCount {
            if let t = displayDoc.page(at: i)?.string,
               !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("\u{2500}\u{2500} Page \(i + 1) \u{2500}\u{2500}\n\(t)")
            }
        }
        return parts.isEmpty ? "No selectable text found in this PDF." : parts.joined(separator: "\n\n")
    }

    /// Render a single PDF page to a UIImage at the given scale multiplier.
    private func renderPageImage(_ page: PDFPage, scale: CGFloat) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {

                // ── Title bar ─────────────────────────────────────────────
                let displayTitle = soTitle.isEmpty ? title : soTitle
                Text(displayTitle)
                    .font(.system(size: 11, weight: soTitle.isEmpty ? .regular : .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(soTitle.isEmpty ? 0.4 : 0.65))
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 16)
                    .padding(.top, safeArea.top + 8)
                    .padding(.bottom, 8)

                Divider().opacity(0.12)

                // ── Content ───────────────────────────────────────────────
                if showOcrMode {
                    GeometryReader { geo in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(0..<displayDoc.pageCount, id: \.self) { i in
                                    if let page = displayDoc.page(at: i) {
                                        OcrPageView(page: page,
                                                    availableWidth: geo.size.width - 16,
                                                    scaleFactor: scaleFactor)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                        }
                    }
                } else if showTextMode {
                    GeometryReader { geo in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(0..<displayDoc.pageCount, id: \.self) { i in
                                    if let page = displayDoc.page(at: i),
                                       let img = renderPageImage(page, scale: scaleFactor * 3.0) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geo.size.width - 16)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                        }
                    }
                } else {
                    PdfKitView(document: displayDoc, currentPageIdx: $currentPage,
                               singlePage: singlePageMode)
                }

                Divider().opacity(0.12)

                // ── Bottom bar ──────────────────────────────────────────────────────
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

                    // PDF segment
                    barSegment(label: "PDF", active: !showTextMode && !showOcrMode) {
                        showTextMode = false; showOcrMode = false
                    }

                    // TEXT segment
                    barSegment(label: "TEXT", active: showTextMode) {
                        showTextMode = true; showOcrMode = false
                    }

                    // SCAN segment
                    barSegment(label: "SCAN", active: showOcrMode) {
                        showOcrMode = true; showTextMode = false
                    }

                    Divider().frame(height: 20).opacity(0.2)

                    // Single page toggle
                    Button { singlePageMode.toggle() } label: {
                        Image(systemName: singlePageMode ? "doc" : "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundColor(singlePageMode ? .orange : .white.opacity(0.45))
                            .padding(.horizontal, 8).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    // Text size controls (TEXT / SCAN mode)
                    if showTextMode || showOcrMode {
                        Divider().frame(height: 20).opacity(0.2)

                        Button { scaleFactor = max(0.5, scaleFactor - 0.25) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 13))
                                .foregroundColor(scaleFactor <= 0.5 ? .white.opacity(0.2) : .white.opacity(0.55))
                                .padding(.horizontal, 6).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Button { scaleFactor = min(4.0, scaleFactor + 0.25) } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 13))
                                .foregroundColor(scaleFactor >= 4.0 ? .white.opacity(0.2) : .white.opacity(0.55))
                                .padding(.horizontal, 6).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if scaleFactor != 1.0 {
                            Button { scaleFactor = 1.0 } label: {
                                Text("\(Int(scaleFactor * 100))%")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.orange.opacity(0.7))
                                    .padding(.horizontal, 4).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    Divider().frame(height: 20).opacity(0.2)

                    // Sort button (right)
                    Button { showSortSheet = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.white.opacity(0.05))
                .padding(.bottom, safeArea.bottom)
            }
        }
        .onAppear { soTitle = soDisplayTitle(from: displayDoc) }
        .sheet(isPresented: $showSortSheet) {
            PdfSortSheet(document: displayDoc) { field in
                let s = sortedDoc(displayDoc, by: field)
                displayDoc = s
                currentPage = 0
                soTitle = soDisplayTitle(from: s)
            }
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
    }

    private func barSegment(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? .black : .white.opacity(0.45))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? Color.white.opacity(0.88) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 3).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort Sheet

private struct PdfSortSheet: View {
    let document: PDFDocument
    let onSort: (PdfSortField) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pdfSortSearchText") private var searchText: String = ""
    @AppStorage("pdfSortSearchHistory") private var historyRaw: String = ""
    @State private var matchingPages: [Int] = []
    @State private var showHistory: Bool = false
    @FocusState private var searchFocused: Bool

    private var history: [String] {
        historyRaw.isEmpty ? [] : historyRaw.components(separatedBy: "\u{001F}")
    }

    private func addToHistory(_ query: String) {
        var list = history.filter { $0 != query }
        list.insert(query, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        historyRaw = list.joined(separator: "\u{001F}")
    }

    var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("SORT PAGES BY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(3)
                    .padding(.top, 22).padding(.bottom, 12)

                // Search bar — searches PDF text content
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    TextField("Search PDF text\u{2026}", text: $searchText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .tint(.orange)
                        .focused($searchFocused)
                        .onSubmit { performSearch() }
                        .submitLabel(.search)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            matchingPages = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.bottom, 0)
                .onTapGesture { showHistory = true }

                // Recent searches dropdown
                if showHistory && !history.isEmpty && searchText.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(history, id: \.self) { item in
                            Button {
                                searchText = item
                                showHistory = false
                                performSearch()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.3))
                                    Text(item)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.75))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.opacity)
                }

                // Search results indicator
                if !searchText.isEmpty && !matchingPages.isEmpty {
                    Text("\(matchingPages.count) page\(matchingPages.count == 1 ? "" : "s") matched")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.7))
                        .padding(.top, 8).padding(.bottom, 12)
                } else if !searchText.isEmpty && matchingPages.isEmpty {
                    Text("No matches")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 8).padding(.bottom, 12)
                } else {
                    Spacer().frame(height: 12)
                }

                VStack(spacing: 0) {
                    ForEach(Array(PdfSortField.allCases.enumerated()), id: \.element.id) { idx, field in
                        if idx > 0 { Divider().opacity(0.1).padding(.leading, 54) }
                        Button {
                            onSort(field)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: field.systemImage)
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 26)
                                Text(field.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.88))
                                Spacer()
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            .padding(.horizontal, 20).padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { matchingPages = []; return }
        showHistory = false
        addToHistory(searchText)
        let query = searchText.lowercased()
        var pages: [Int] = []
        for i in 0..<document.pageCount {
            if let text = document.page(at: i)?.string?.lowercased(),
               text.contains(query) {
                pages.append(i + 1)
            }
        }
        matchingPages = pages
    }
}

// MARK: - OCR Page View

private struct OcrPageView: View {
    let page: PDFPage
    let availableWidth: CGFloat
    let scaleFactor: CGFloat

    @State private var pageImage: UIImage?
    @State private var textBlocks: [TextBlock] = []
    @State private var isProcessing = true

    private struct TextBlock: Identifiable, Sendable {
        let id = UUID()
        let text: String
        let box: CGRect
    }

    var body: some View {
        ZStack {
            if let img = pageImage {
                let aspect = img.size.height / img.size.width
                let h = availableWidth * aspect

                ZStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: availableWidth)
                        .opacity(0.35)

                    ForEach(textBlocks) { block in
                        let bx = block.box.origin.x * availableWidth
                        let by = (1 - block.box.origin.y - block.box.height) * h
                        let bw = block.box.width * availableWidth
                        let bh = block.box.height * h

                        Text(block.text)
                            .font(.system(size: max(4, bh * 0.72 * scaleFactor),
                                          design: .monospaced))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                            .frame(width: bw, height: bh, alignment: .leading)
                            .background(Color.black.opacity(0.45))
                            .position(x: bx + bw / 2, y: by + bh / 2)
                    }
                    .frame(width: availableWidth, height: h)

                    if isProcessing {
                        ProgressView().tint(.orange)
                    }
                }
                .frame(width: availableWidth, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: availableWidth * 1.414)
                    .overlay { ProgressView().tint(.orange) }
            }
        }
        .task { await processPage() }
    }

    private func processPage() async {
        let bounds = page.bounds(for: .mediaBox)
        let renderScale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * renderScale,
                          height: bounds.height * renderScale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: renderScale, y: -renderScale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        pageImage = img

        guard let cgImage = img.cgImage else { isProcessing = false; return }

        let blocks = await withCheckedContinuation { (cont: CheckedContinuation<[TextBlock], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                let results: [TextBlock] = (request.results ?? []).compactMap { obs in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    return TextBlock(text: text, box: obs.boundingBox)
                }
                cont.resume(returning: results)
            }
        }

        textBlocks = blocks
        isProcessing = false
    }
}

// MARK: - PDFKit View

private struct PdfKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIdx: Int
    var singlePage: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(binding: $currentPageIdx) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = singlePage ? .singlePage : .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.usePageViewController(singlePage)
        view.document = document
        // Restore saved position
        if currentPageIdx > 0, let page = document.page(at: currentPageIdx) {
            DispatchQueue.main.async { view.go(to: page) }
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Swap document when sort is applied
        if uiView.document !== document {
            uiView.document = document
            if let first = document.page(at: 0) {
                uiView.go(to: first)
            }
        }
        // Display mode + swipe navigation
        let mode: PDFDisplayMode = singlePage ? .singlePage : .singlePageContinuous
        if uiView.displayMode != mode {
            uiView.displayMode = mode
            uiView.usePageViewController(singlePage)
        }
    }

    final class Coordinator: NSObject {
        @Binding var currentPageIdx: Int
        init(binding: Binding<Int>) { _currentPageIdx = binding }

        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView,
                  let doc  = pdfView.document,
                  let page = pdfView.currentPage else { return }
            let idx = doc.index(for: page)
            guard idx != NSNotFound else { return }
            DispatchQueue.main.async { self.currentPageIdx = idx }
        }
    }
}
