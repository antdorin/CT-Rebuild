import SwiftUI
import PDFKit
import WebKit

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

    @State private var showSortSheet = false
    @State private var displayDoc: PDFDocument
    @State private var soTitle: String = ""
    @State private var singlePageMode = false
    @State private var autoCropEnabled = true
    @State private var showReflowMode = false
    @State private var reflowFontPercent = 100

    init(document: PDFDocument, title: String, safeArea: EdgeInsets,
         currentPage: Binding<Int>, onBack: @escaping () -> Void) {
        self.document    = document
        self.title       = title
        self.safeArea    = safeArea
        self._currentPage = currentPage
        self.onBack      = onBack
        self._displayDoc = State(initialValue: document)
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
                if showReflowMode {
                    ReflowWebView(document: displayDoc, fontPercent: reflowFontPercent)
                } else {
                    PdfKitView(document: displayDoc, currentPageIdx: $currentPage,
                               singlePage: singlePageMode, autoCrop: autoCropEnabled)
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

                    modeSegment(label: "PDF", active: !showReflowMode) {
                        showReflowMode = false
                    }

                    modeSegment(label: "REFLOW", active: showReflowMode) {
                        showReflowMode = true
                    }

                    Divider().frame(height: 20).opacity(0.2)

                    if showReflowMode {
                        Button { reflowFontPercent = max(70, reflowFontPercent - 10) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 13))
                                .foregroundColor(reflowFontPercent <= 70 ? .white.opacity(0.2) : .white.opacity(0.55))
                                .padding(.horizontal, 6).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Button { reflowFontPercent = min(220, reflowFontPercent + 10) } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 13))
                                .foregroundColor(reflowFontPercent >= 220 ? .white.opacity(0.2) : .white.opacity(0.55))
                                .padding(.horizontal, 6).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Button { reflowFontPercent = 100 } label: {
                            Text("\(reflowFontPercent)%")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.7))
                                .padding(.horizontal, 4).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Auto-crop toggle
                        Button { autoCropEnabled.toggle() } label: {
                            Image(systemName: autoCropEnabled ? "crop" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13))
                                .foregroundColor(autoCropEnabled ? .orange : .white.opacity(0.45))
                                .padding(.horizontal, 8).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        // Single page toggle
                        Button { singlePageMode.toggle() } label: {
                            Image(systemName: singlePageMode ? "doc" : "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundColor(singlePageMode ? .orange : .white.opacity(0.45))
                                .padding(.horizontal, 8).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
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

    private func modeSegment(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? .black : .white.opacity(0.45))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(active ? Color.white.opacity(0.88) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 2).padding(.vertical, 4)
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

// MARK: - Auto-Crop Helpers

/// Scans a PDF page bitmap to find the bounding box of non-white content.
/// Returns the crop rect in PDF page coordinate space, or nil if the page is blank.
private func contentBounds(for page: PDFPage, threshold: UInt8 = 245) -> CGRect? {
    let mediaBox = page.bounds(for: .mediaBox)
    let sampleScale: CGFloat = 1.0   // 1× is enough for edge detection
    let w = Int(mediaBox.width * sampleScale)
    let h = Int(mediaBox.height * sampleScale)
    guard w > 0, h > 0 else { return nil }

    // Render page to a 32-bit RGBA bitmap
    let bytesPerRow = w * 4
    guard let ctx = CGContext(data: nil, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    ctx.setFillColor(UIColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: sampleScale, y: -sampleScale)
    page.draw(with: .mediaBox, to: ctx)

    guard let data = ctx.data else { return nil }
    let ptr = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * h)

    var minX = w, minY = h, maxX = 0, maxY = 0

    for y in 0..<h {
        let row = y * bytesPerRow
        for x in 0..<w {
            let offset = row + x * 4
            let r = ptr[offset], g = ptr[offset + 1], b = ptr[offset + 2]
            if r < threshold || g < threshold || b < threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }

    guard maxX >= minX, maxY >= minY else { return nil }

    // Add a small margin (4pt equivalent)
    let margin: CGFloat = 4.0 * sampleScale
    let cx = max(0, CGFloat(minX) - margin)
    let cy = max(0, CGFloat(minY) - margin)
    let cw = min(CGFloat(w), CGFloat(maxX) + margin) - cx
    let ch = min(CGFloat(h), CGFloat(maxY) + margin) - cy

    // Convert pixel coords back to PDF page coords (flip Y)
    return CGRect(x: cx / sampleScale,
                  y: (CGFloat(h) - cy - ch) / sampleScale,
                  width: cw / sampleScale,
                  height: ch / sampleScale)
}

/// Returns a new PDFDocument with each page's cropBox set to its content bounds.
private func autoCropped(_ source: PDFDocument) -> PDFDocument {
    let out = PDFDocument()
    for i in 0..<source.pageCount {
        guard let page = source.page(at: i),
              let copy = page.copy() as? PDFPage else { continue }
        if let crop = contentBounds(for: copy) {
            copy.setBounds(crop, for: .cropBox)
        }
        out.insert(copy, at: i)
    }
    return out
}

private func htmlEscaped(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private struct TicketFields {
    var soNumber: String = ""
    var date: String = ""
    var shipToHtml: String = ""
    var notes: String = ""

    var companyName: String = ""
    var terms: String = ""
    var shippingMethod: String = ""
    var thirdPartyAccount: String = ""

    var binLocation: String = ""
    var itemCode: String = ""
    var itemDescription: String = ""
    var quantity: String = ""
    var units: String = ""
    var committed: String = ""
}

private func firstMatch(_ text: String, _ pattern: String, options: NSRegularExpression.Options = []) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options),
          let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range, in: text)
    else { return "" }
    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func firstCapture(_ text: String, _ pattern: String, options: NSRegularExpression.Options = []) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options),
          let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text)
    else { return "" }
    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func splitColumns(_ line: String) -> [String] {
    let normalized = line.replacingOccurrences(
        of: #"\s{2,}"#,
        with: "\t",
        options: .regularExpression
    )
    return normalized
        .split(separator: "\t")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func extractLineAfterHeader(_ text: String, headerPattern: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: headerPattern, options: [.anchorsMatchLines, .caseInsensitive]),
          let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let full = Range(match.range, in: text)
    else { return [] }

    let tail = String(text[full.upperBound...])
    let lines = tail
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return lines
}

private func parseTicketFields(from text: String) -> TicketFields {
    var fields = TicketFields()

    fields.soNumber = firstMatch(text, #"SO-[A-Za-z0-9]+-[A-Za-z0-9]+"#)
    fields.date = firstMatch(text, #"\b(?:0?[1-9]|1[0-2])/(?:0?[1-9]|[12][0-9]|3[01])/\d{4}\b"#)

    let shipToBlock = firstCapture(text, #"(?is)Ship\s*To\s*:?[\s\n]*(.*?)[\s\n]*Notes\s*:?"#)
    if !shipToBlock.isEmpty {
        fields.shipToHtml = shipToBlock
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(htmlEscaped)
            .joined(separator: "<br />")
    }
    fields.notes = firstCapture(text, #"(?is)Notes\s*:?[\s\n]*(.*?)(?:\n\s*Company\s+Name|\n\s*Bin\s+Location|$)"#)

    let companyLines = extractLineAfterHeader(
        text,
        headerPattern: #"^\s*Company\s+Name\s+Terms\s+Shipping\s+Method\s+3rd\s+Party\s+Account\s*#?\s*$"#
    )
    if let row = companyLines.first {
        let cols = splitColumns(row)
        if cols.count > 0 { fields.companyName = cols[0].trimmingCharacters(in: .whitespaces) }
        if cols.count > 1 { fields.terms = cols[1].trimmingCharacters(in: .whitespaces) }
        if cols.count > 2 { fields.shippingMethod = cols[2].trimmingCharacters(in: .whitespaces) }
        if cols.count > 3 { fields.thirdPartyAccount = cols[3].trimmingCharacters(in: .whitespaces) }
    }

    let itemLines = extractLineAfterHeader(
        text,
        headerPattern: #"^\s*Bin\s+Location\s+Item\s+Quantity\s+Units\s+Committed\s*$"#
    )
    if let row = itemLines.first {
        let cols = splitColumns(row)
        if cols.count > 0 { fields.binLocation = cols[0].trimmingCharacters(in: .whitespaces) }
        if cols.count > 1 { fields.itemCode = cols[1].trimmingCharacters(in: .whitespaces) }
        if cols.count > 2 { fields.quantity = cols[2].trimmingCharacters(in: .whitespaces) }
        if cols.count > 3 { fields.units = cols[3].trimmingCharacters(in: .whitespaces) }
        if cols.count > 4 { fields.committed = cols[4].trimmingCharacters(in: .whitespaces) }
    }
    if itemLines.count > 1 {
        fields.itemDescription = itemLines[1]
    }

    return fields
}

private func ticketSectionHTML(fields: TicketFields, page: Int) -> String {
    let notes = fields.notes.isEmpty ? "" : htmlEscaped(fields.notes)
    let shipTo = fields.shipToHtml

    return """
    <section class=\"ticket\">
      <div class=\"ticket-inner\">
                <div class=\"top-row\">
                    <div class=\"doc-meta\">
                        <div class=\"title\">Picking Ticket</div>
                        <div class=\"so\">#\(htmlEscaped(fields.soNumber))</div>
                        <div class=\"date\">\(htmlEscaped(fields.date))</div>
                    </div>
                    <table class=\"check-grid\" cellspacing=\"0\" cellpadding=\"0\">
                        <tr><th></th><th>Employee</th><th>Date</th></tr>
                        <tr><th>Picked</th><td></td><td></td></tr>
                        <tr><th>Checked</th><td></td><td></td></tr>
                    </table>
                </div>

                <div class=\"address-row\">
                    <div class=\"panel\">
                        <div class=\"panel-title\">Ship To</div>
                        <div class=\"panel-body\">\(shipTo)</div>
                    </div>
                    <div class=\"panel\">
                        <div class=\"panel-title\">Notes:</div>
                        <div class=\"panel-body\">\(notes)</div>
                    </div>
                </div>

                <table class=\"meta-table\" cellspacing=\"0\" cellpadding=\"0\">
                    <tr>
                        <th>Company Name</th>
                        <th>Terms</th>
                        <th>Shipping Method</th>
                        <th>3rd Party Account #</th>
                    </tr>
                    <tr>
                        <td>\(htmlEscaped(fields.companyName))</td>
                        <td>\(htmlEscaped(fields.terms))</td>
                        <td>\(htmlEscaped(fields.shippingMethod))</td>
                        <td>\(htmlEscaped(fields.thirdPartyAccount))</td>
                    </tr>
                </table>

                <table class=\"item-table\" cellspacing=\"0\" cellpadding=\"0\">
                    <tr>
                        <th>Bin Location</th>
                        <th>Item</th>
                        <th>Quantity</th>
                        <th>Units</th>
                        <th>Committed</th>
                    </tr>
                    <tr>
                        <td>\(htmlEscaped(fields.binLocation))</td>
                        <td><strong>\(htmlEscaped(fields.itemCode))</strong></td>
                        <td>\(htmlEscaped(fields.quantity))</td>
                        <td>\(htmlEscaped(fields.units))</td>
                        <td>\(htmlEscaped(fields.committed))</td>
                    </tr>
                </table>

                <div class=\"item-desc\">\(htmlEscaped(fields.itemDescription))</div>
                <div class=\"page-label\">Page \(page)</div>
      </div>
    </section>
    """
}

private func buildReflowHTML(from doc: PDFDocument, fontPercent: Int) -> String {
    var pages: [String] = []
    for i in 0..<doc.pageCount {
        let raw = (doc.page(at: i)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { continue }
        let fields = parseTicketFields(from: raw)
        pages.append(ticketSectionHTML(fields: fields, page: i + 1))
    }

    let content = pages.isEmpty
        ? "<section class=\"empty\">No selectable text found in this PDF.</section>"
        : pages.joined(separator: "\n")

    return """
    <!doctype html>
    <html>
    <head>
      <meta charset=\"utf-8\" />
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0\" />
      <style>
        :root { --fontScale: \(fontPercent)%; }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          padding: 10px;
          background: #0f0f0f;
          color: #111;
          font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif;
        }
        .ticket {
          background: #dcdcdc;
          border-radius: 10px;
          margin: 0 0 10px 0;
          overflow: hidden;
        }
        .ticket-inner {
                    width: 100%;
                    min-height: 100vw;
                    max-width: 980px;
                    margin: 0 auto;
                    padding: 22px 18px 16px;
                    display: grid;
                    gap: 10px;
                }

                .top-row {
                    display: grid;
                    grid-template-columns: 1.1fr 0.9fr;
                    gap: 12px;
                    align-items: start;
                }
                .title { font-size: calc(30px * var(--fontScale) / 100); font-weight: 700; line-height: 1.1; }
                .so { margin-top: 8px; font-size: calc(24px * var(--fontScale) / 100); font-weight: 700; line-height: 1.15; }
                .date { margin-top: 2px; font-size: calc(18px * var(--fontScale) / 100); color: #2b2b2b; }

                .check-grid { width: 100%; border-collapse: collapse; background: #e2e2e2; }
                .check-grid th, .check-grid td {
                    border: 2px solid #232323;
                    padding: 6px;
                    font-size: calc(12px * var(--fontScale) / 100);
                    text-align: left;
                    min-height: 24px;
                }

                .address-row {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 12px;
                }
                .panel {
                    background: #dbdbdb;
                    border: 1px solid #cfcfcf;
                    border-radius: 6px;
                    padding: 8px;
                    min-height: 126px;
                }
                .panel-title {
                    font-size: calc(16px * var(--fontScale) / 100);
                    font-weight: 700;
                    margin-bottom: 6px;
                }
                .panel-body {
                    font-size: calc(13px * var(--fontScale) / 100);
                    line-height: 1.24;
                    white-space: pre-wrap;
                    word-break: break-word;
                }

                .meta-table,
                .item-table {
                    width: 100%;
                    border-collapse: collapse;
                    table-layout: fixed;
                    background: #e0e0e0;
                }
                .meta-table th,
                .meta-table td,
                .item-table th,
                .item-table td {
                    border: 2px solid #2a2a2a;
                    padding: 6px;
                    font-size: calc(12px * var(--fontScale) / 100);
                    text-align: left;
                    vertical-align: top;
                    word-break: break-word;
                }
                .meta-table th,
                .item-table th { background: #d2d2d2; font-weight: 700; }

                .meta-table th:nth-child(1), .meta-table td:nth-child(1) { width: 28%; }
                .meta-table th:nth-child(2), .meta-table td:nth-child(2) { width: 14%; }
                .meta-table th:nth-child(3), .meta-table td:nth-child(3) { width: 26%; }
                .meta-table th:nth-child(4), .meta-table td:nth-child(4) { width: 32%; }

                .item-table th:nth-child(1), .item-table td:nth-child(1) { width: 14%; }
                .item-table th:nth-child(2), .item-table td:nth-child(2) { width: 46%; }
                .item-table th:nth-child(3), .item-table td:nth-child(3) { width: 12%; }
                .item-table th:nth-child(4), .item-table td:nth-child(4) { width: 12%; }
                .item-table th:nth-child(5), .item-table td:nth-child(5) { width: 16%; }

                .item-desc {
                    margin-top: -2px;
                    border: 2px solid #2a2a2a;
                    border-top: 0;
                    background: #e0e0e0;
                    padding: 6px;
                    min-height: 26px;
                    font-size: calc(12px * var(--fontScale) / 100);
                    line-height: 1.2;
                    word-break: break-word;
                }

                .page-label {
                    justify-self: end;
                    font-size: calc(10px * var(--fontScale) / 100);
                    color: #595959;
                    margin-top: 4px;
                }

                @media (max-width: 760px) {
                    .title { font-size: calc(22px * var(--fontScale) / 100); }
                    .so { font-size: calc(20px * var(--fontScale) / 100); }
                    .date { font-size: calc(16px * var(--fontScale) / 100); }
                    .top-row { grid-template-columns: 1fr; }
                    .address-row { grid-template-columns: 1fr; }
                }

        .empty { color: #ddd; padding: 20px; }
      </style>
    </head>
    <body>
      \(content)
    </body>
    </html>
    """
}

// MARK: - Reflow Web View

private struct ReflowWebView: UIViewRepresentable {
        let document: PDFDocument
        let fontPercent: Int

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> WKWebView {
                let config = WKWebViewConfiguration()
                let view = WKWebView(frame: .zero, configuration: config)
                view.isOpaque = false
                view.backgroundColor = .black
                view.scrollView.backgroundColor = .black
                view.scrollView.contentInsetAdjustmentBehavior = .never

                context.coordinator.sourceDoc = document
                context.coordinator.fontPercent = fontPercent
                view.loadHTMLString(buildReflowHTML(from: document, fontPercent: fontPercent), baseURL: nil)
                return view
        }

        func updateUIView(_ uiView: WKWebView, context: Context) {
                let c = context.coordinator
                let docChanged = c.sourceDoc !== document
                let fontChanged = c.fontPercent != fontPercent
                guard docChanged || fontChanged else { return }

                c.sourceDoc = document
                c.fontPercent = fontPercent
                uiView.loadHTMLString(buildReflowHTML(from: document, fontPercent: fontPercent), baseURL: nil)
        }

        final class Coordinator {
                weak var sourceDoc: PDFDocument?
                var fontPercent: Int = 100
        }
}

// MARK: - PDFKit View

private struct PdfKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIdx: Int
    var singlePage: Bool = false
    var autoCrop: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(binding: $currentPageIdx) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = singlePage ? .singlePage : .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.usePageViewController(singlePage)
        let doc = autoCrop ? autoCropped(document) : document
        view.document = doc
        context.coordinator.lastAutoCrop = autoCrop
        context.coordinator.sourceDoc = document
        if currentPageIdx > 0, let page = doc.page(at: currentPageIdx) {
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
        let coord = context.coordinator
        let docChanged = coord.sourceDoc !== document
        let cropChanged = coord.lastAutoCrop != autoCrop

        if docChanged || cropChanged {
            coord.sourceDoc = document
            coord.lastAutoCrop = autoCrop
            let doc = autoCrop ? autoCropped(document) : document
            uiView.document = doc
            let pageIdx = docChanged ? 0 : currentPageIdx
            if let page = doc.page(at: pageIdx) {
                uiView.go(to: page)
            }
        }
        let mode: PDFDisplayMode = singlePage ? .singlePage : .singlePageContinuous
        if uiView.displayMode != mode {
            uiView.displayMode = mode
            uiView.usePageViewController(singlePage)
        }
    }

    final class Coordinator: NSObject {
        @Binding var currentPageIdx: Int
        var lastAutoCrop: Bool = false
        weak var sourceDoc: PDFDocument?
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
