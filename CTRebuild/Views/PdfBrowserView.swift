import SwiftUI
import PDFKit

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

// MARK: - Date Extraction from filename

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
    let dateLabel: String
    let sortDate: Date
    let filenames: [String]
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

private func groupFiles(_ files: [String]) -> [PdfDateGroup] {
    var byKey: [String: (Date, [String])] = [:]
    let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .none
    for file in files {
        if let date = extractDate(from: file) {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
            if byKey[key] == nil { byKey[key] = (date, []) }
            byKey[key]!.1.append(file)
        } else {
            byKey["z_\(file)"] = (Date.distantPast, [file])
        }
    }
    return byKey
        .map { key, v in
            PdfDateGroup(id: key,
                         dateLabel: v.0 == .distantPast ? "No Date" : df.string(from: v.0),
                         sortDate:  v.0,
                         filenames: v.1.sorted())
        }
        .sorted { $0.sortDate > $1.sortDate }
}

private func mergePDFs(from parts: [Data]) -> PDFDocument {
    let out = PDFDocument()
    var idx = 0
    for data in parts {
        guard let doc = PDFDocument(data: data) else { continue }
        for p in 0..<doc.pageCount {
            if let page = doc.page(at: p) { out.insert(page, at: idx); idx += 1 }
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
    for (i, (page, _)) in sorted.enumerated() { out.insert(page, at: i) }
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let group = openedGroup, let doc = mergedDoc {
                PdfDetailView(
                    document: doc,
                    title: group.dateLabel,
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
        Button { Task { await openGroup(group) } } label: {
            HStack(spacing: 14) {
                Image(systemName: group.filenames.count > 1 ? "doc.on.doc" : "doc")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.dateLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(group.filenames.count == 1
                         ? group.filenames[0]
                         : "\(group.filenames.count) PDFs \u{2013} merged on open")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1).truncationMode(.middle)
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
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func loadFiles() async {
        isLoading = true; errorMessage = nil
        do {
            let files = try await HubClient.shared.fetchPdfList()
            groups = groupFiles(files)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openGroup(_ group: PdfDateGroup) async {
        isLoadingGroup = true; groupError = nil
        do {
            var parts: [Data] = []
            for filename in group.filenames {
                parts.append(try await HubClient.shared.fetchPdf(filename: filename))
            }
            let doc = mergePDFs(from: parts)
            withAnimation(.easeInOut(duration: 0.22)) {
                mergedDoc = doc
                openedGroup = group
            }
        } catch {
            groupError = error.localizedDescription
        }
        isLoadingGroup = false
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
                if showTextMode {
                    ScrollView {
                        Text(extractedText)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .textSelection(.enabled)
                    }
                } else {
                    PdfKitView(document: displayDoc, currentPageIdx: $currentPage)
                }

                Divider().opacity(0.12)

                // ── Bottom bar: [ ← Back ][ PDF ][ TEXT ][ ⊞ ] ───────────
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
                    barSegment(label: "PDF", active: !showTextMode) { showTextMode = false }

                    // TEXT segment
                    barSegment(label: "TEXT", active: showTextMode) { showTextMode = true }

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
            PdfSortSheet { field in
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
    let onSort: (PdfSortField) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("SORT PAGES BY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(3)
                    .padding(.top, 22).padding(.bottom, 16)

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
}

// MARK: - PDFKit View

private struct PdfKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIdx: Int

    func makeCoordinator() -> Coordinator { Coordinator(binding: $currentPageIdx) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
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
}

// MARK: - PDFKit View

private struct PdfKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIdx: Int

    func makeCoordinator() -> Coordinator { Coordinator(binding: $currentPageIdx) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.document = document
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
        if uiView.document !== document {
            uiView.document = document
            if let first = document.page(at: 0) { uiView.go(to: first) }
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
}
