import SwiftUI
import PDFKit
import UIKit

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
    let sourceCatalog: SourceCatalog?
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
                                filenames: filenames,
                                sourceCatalog: v.1.compactMap { meta in
                                    guard let raw = meta.sourceCatalog else { return nil }
                                    return SourceCatalog(rawValue: raw)
                                }.first)
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

    // per-group last-page memory (group.id → page index) — persisted to UserDefaults
    @State private var lastPages: [String: Int] = [:]

    // per-group cached merged PDFDocuments (for bin extraction without re-download)
    @State private var cachedDocs: [String: PDFDocument] = [:]

    // persists which group was open when the panel closed
    @AppStorage("pdfOpenedGroupId") private var openedGroupId: String = ""
    @AppStorage("panel_showMaterial") private var showMaterial = true

    @ObservedObject private var binStore = BinDataStore.shared

    var body: some View {
        ZStack {
            if showMaterial {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }

            if let group = openedGroup, let doc = mergedDoc {
                PdfDetailView(
                    document: doc,
                    title: group.soLabel.isEmpty ? group.dateLabel : group.soLabel,
                    safeArea: safeArea,
                    filenames: group.filenames,
                    currentPage: Binding(
                        get: { lastPages[group.id] ?? 0 },
                        set: { newPage in
                            var updated = lastPages
                            updated[group.id] = newPage
                            lastPages = updated
                            UserDefaults.standard.set(updated, forKey: "pdfLastPages")
                        }
                    ),
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            openedGroup = nil
                            mergedDoc = nil
                            openedGroupId = ""
                        }
                    }
                )
            } else {
                fileListContent
            }
        }
        .task {
            if let stored = UserDefaults.standard.dictionary(forKey: "pdfLastPages") as? [String: Int] {
                lastPages = stored
            }
            await loadFiles()
            // Restore previously opened group
            if openedGroup == nil, !openedGroupId.isEmpty,
               let group = groups.first(where: { $0.id == openedGroupId }) {
                await openGroup(group)
            }
        }
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
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
            if !binStore.isActive(groupId: group.id) {
                let label = group.soLabel.isEmpty ? group.dateLabel : group.soLabel
                binStore.activate(groupId: group.id, label: label, document: doc)
            }
            if let sourceCatalog = group.sourceCatalog {
                await MainActor.run { ScanStore.shared.setActiveTicketCatalog(sourceCatalog) }
            } else {
                do {
                    let context = try await HubClient.shared.fetchPdfContext()
                    if let parsed = SourceCatalog(rawValue: context.sourceCatalog) {
                        await MainActor.run { ScanStore.shared.setActiveTicketCatalog(parsed) }
                    }
                } catch {
                    // keep current context when context endpoint is unavailable
                }
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                mergedDoc = doc
                openedGroup = group
                openedGroupId = group.id
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
                let label = group.soLabel.isEmpty ? group.dateLabel : group.soLabel
                binStore.activate(groupId: group.id, label: label, document: doc)
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

// MARK: - View Mode Enum

private enum ViewMode: String { case pdf, reader }

// MARK: - PDF Detail View

private struct PdfDetailView: View {
    let document: PDFDocument
    let title: String
    let safeArea: EdgeInsets
    let filenames: [String]
    @Binding var currentPage: Int
    let onBack: () -> Void

    @State private var displayDoc: PDFDocument
    @State private var soTitle: String = ""
    @AppStorage("pdfSinglePageMode") private var singlePageMode = false
    @State private var autoCropEnabled = true
    @AppStorage("pdfViewMode") private var viewMode: ViewMode = .pdf
    @State private var isPicked: Bool = false
    @State private var isShipped: Bool = false
    @State private var pdfOverrides: PdfOverridesPayload = .empty
    @AppStorage("panel_showMaterial") private var showMaterial = true

    init(document: PDFDocument, title: String, safeArea: EdgeInsets,
         filenames: [String] = [],
         currentPage: Binding<Int>, onBack: @escaping () -> Void) {
        self.document     = document
        self.title        = title
        self.safeArea     = safeArea
        self.filenames    = filenames
        self._currentPage = currentPage
        self.onBack       = onBack
        self._displayDoc  = State(initialValue: document)
    }

    var body: some View {
        ZStack {
            if showMaterial {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }
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
                ZStack {
                    if viewMode == .pdf {
                        PdfKitView(document: displayDoc, currentPageIdx: $currentPage,
                                   singlePage: singlePageMode,
                                   autoCrop: autoCropEnabled,
                                   overrides: pdfOverrides)
                    } else {
                        NativeReaderView(document: displayDoc, filenames: filenames, singlePage: singlePageMode)
                    }
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

                    modeSegment(label: "PDF", active: viewMode == .pdf) {
                        viewMode = .pdf
                    }

                    modeSegment(label: "READER", active: viewMode == .reader) {
                        viewMode = .reader
                    }

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

                    switch viewMode {
                    case .pdf:
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
                    case .reader:
                        // Single page toggle (same behaviour as PDF tab)
                        Button { singlePageMode.toggle() } label: {
                            Image(systemName: singlePageMode ? "doc" : "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundColor(singlePageMode ? .orange : .white.opacity(0.45))
                                .padding(.horizontal, 8).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .background(Color.white.opacity(0.05))
                .padding(.bottom, safeArea.bottom)
            }
        }
        .onAppear {
            soTitle = soDisplayTitle(from: displayDoc)
            isPicked  = UserDefaults.standard.bool(forKey: "docpicked:\(title)")
            isShipped = UserDefaults.standard.bool(forKey: "docshipped:\(title)")
        }
        .task(id: filenames.joined(separator: "|")) {
            await loadPdfOverrides()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task { await loadPdfOverrides() }
        }
    }

    private func loadPdfOverrides() async {
        guard let filename = filenames.first else {
            await MainActor.run { pdfOverrides = .empty }
            return
        }

        do {
            let fetched = try await HubClient.shared.fetchPdfOverrides(filename: filename)
            await MainActor.run { pdfOverrides = fetched }
        } catch {
            await MainActor.run { pdfOverrides = .empty }
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

// MARK: - PDFKit View

private struct PdfKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIdx: Int
    var singlePage: Bool = false
    var autoCrop: Bool = false
    var overrides: PdfOverridesPayload = .empty

    func makeCoordinator() -> Coordinator { Coordinator(binding: $currentPageIdx) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = singlePage ? .singlePage : .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.usePageViewController(singlePage)
        let source = autoCrop ? autoCropped(document) : document
        let doc = composedDocument(from: source, overrides: overrides)
        view.document = doc
        context.coordinator.lastAutoCrop = autoCrop
        context.coordinator.sourceDoc = document
        context.coordinator.lastOverrides = overrides
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
        let overridesChanged = coord.lastOverrides != overrides

        if docChanged || cropChanged || overridesChanged {
            coord.sourceDoc = document
            coord.lastAutoCrop = autoCrop
            coord.lastOverrides = overrides
            let source = autoCrop ? autoCropped(document) : document
            let doc = composedDocument(from: source, overrides: overrides)
            uiView.document = doc
            // Re-trigger auto-scaling after document replacement; without this the
            // page can render smaller than the view following an overrides update.
            uiView.autoScales = true
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

    private func composedDocument(from source: PDFDocument, overrides: PdfOverridesPayload) -> PDFDocument {
        guard overrides.hasEdits else { return source }

        let out = PDFDocument()
        for pageIdx in 0..<source.pageCount {
            guard let page = source.page(at: pageIdx),
                  let copy = page.copy() as? PDFPage else { continue }

            applyOverrides(to: copy, pageNumber: pageIdx + 1, overrides: overrides)
            out.insert(copy, at: out.pageCount)
        }

        return out
    }

    private func applyOverrides(to page: PDFPage, pageNumber: Int, overrides: PdfOverridesPayload) {
        var pageRuns: [(runIndex: Int, run: PdfRunOverride)] = overrides.runs
            .compactMap { key, value in
                guard let (pageIdx, runIdx) = parseRunKey(key), pageIdx == pageNumber else { return nil }
                return (runIdx, value)
            }
            .sorted { lhs, rhs in lhs.runIndex < rhs.runIndex }

        let runLayouts = pageRunLayouts(from: page)

        if pageRuns.isEmpty {
            guard overrides.global != .defaults else { return }
            guard !runLayouts.isEmpty else { return }
            let syntheticCount = min(24, runLayouts.count)
            pageRuns = (0..<syntheticCount).map { index in
                (runIndex: index, run: PdfRunOverride())
            }
        }

        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Edited-only mode: hide the original PDF content and render only override text.
        addFullPageWhiteout(to: page, bounds: bounds)

        let global = overrides.global
        let zoomX = max(0.1, global.pageZoomX)
        let zoomY = max(0.1, global.pageZoomY)
        let pageScaleX = max(0.1, global.pageSizeX)
        let pageScaleY = max(0.1, global.pageSizeY)
        let textScaleX = max(0.4, global.textSizeX)

        for entry in pageRuns {
            guard let layout = runLayout(for: entry.runIndex, runLayouts: runLayouts) else { continue }

            let runScale = max(0.2, entry.run.sizeScale)
            let baseFontSize = max(8.0, layout.bounds.height)
            let fontSize = max(8.0, baseFontSize * global.textSizeY * runScale)
            let lineText = layout.text

            let font = resolvedFont(
                fontName: global.fontOverride,
                size: fontSize,
                forceBold: global.forceBold
            )

            let rowHeight = max(fontSize * 1.35, layout.bounds.height * global.textSizeY * runScale) * pageScaleY
            let estimatedWidth = max(24.0, min(bounds.width - 4.0, layout.bounds.width * textScaleX)) * pageScaleX

            let centeredX = ((layout.bounds.minX - bounds.midX) * zoomX) + bounds.midX
            // Anchor on word TOP (maxY in PDF coords) to match desktop which draws at the
            // top-left of each word. Annotation bottom = word_top_zoomed - rowHeight so
            // the annotation's visual top aligns with the word's zoomed top edge.
            let centeredYtop = ((layout.bounds.maxY - bounds.midY) * zoomY) + bounds.midY
            var x = bounds.minX + ((centeredX - bounds.minX) * pageScaleX)
            var y = bounds.minY + ((centeredYtop - rowHeight - bounds.minY) * pageScaleY)
            x += CGFloat(entry.run.dx)
            y += CGFloat(entry.run.dy)

            let minX = bounds.minX + 8.0
            let maxX = max(minX, bounds.maxX - estimatedWidth - 8.0)
            let minY = bounds.minY + 8.0
            let maxY = max(minY, bounds.maxY - rowHeight - 8.0)
            x = min(max(x, minX), maxX)
            y = min(max(y, minY), maxY)

            let annotation = PDFAnnotation(
                bounds: CGRect(x: x, y: y, width: estimatedWidth, height: rowHeight),
                forType: .freeText,
                withProperties: nil
            )
            let textBorder = PDFBorder()
            textBorder.lineWidth = 0
            annotation.contents = lineText
            annotation.font = font
            annotation.fontColor = UIColor.black.withAlphaComponent(0.88)
            annotation.color = .clear
            annotation.interiorColor = .clear
            annotation.border = textBorder
            // Force PDF-level border suppression — PDFKit's color/.clear alone is not
            // always honoured when the document is re-rendered.
            annotation.setValue([0.0, 0.0, 0.0] as NSArray,
                                forAnnotationKey: PDFAnnotationKey(rawValue: "/Border"))
            annotation.setValue(["W": 0, "S": "S"] as NSDictionary,
                                forAnnotationKey: PDFAnnotationKey(rawValue: "/BS"))
            annotation.alignment = .left
            annotation.shouldDisplay = true
            annotation.shouldPrint = true

            page.addAnnotation(annotation)
        }
    }

    private func addFullPageWhiteout(to page: PDFPage, bounds: CGRect) {
        let whiteout = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        // Use white for both fill and border so any border fallback is invisible.
        whiteout.color = .white
        whiteout.interiorColor = .white
        let border = PDFBorder()
        border.lineWidth = 0
        whiteout.border = border
        whiteout.setValue([0.0, 0.0, 0.0] as NSArray,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/Border"))
        whiteout.setValue(["W": 0, "S": "S"] as NSDictionary,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/BS"))
        whiteout.shouldDisplay = true
        whiteout.shouldPrint = true
        page.addAnnotation(whiteout)
    }

    private func parseRunKey(_ key: String) -> (Int, Int)? {
        let parts = key.split(separator: ":")
        guard parts.count == 2 else { return nil }

        let pagePart = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "p"))
        let runPart = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "r"))
        guard let page = Int(pagePart), let run = Int(runPart) else { return nil }
        return (page, run)
    }

    private func pageRunLayouts(from page: PDFPage) -> [(text: String, bounds: CGRect)] {
        guard let rawText = page.string else { return [] }

        let nsText = rawText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let wordRegex = try? NSRegularExpression(pattern: #"\S+"#) else {
            return pageLineLayouts(from: page)
        }

        var runLayouts: [(text: String, bounds: CGRect)] = []
        for match in wordRegex.matches(in: rawText, options: [], range: fullRange) {
            let token = nsText.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty,
                  let tokenSelection = page.selection(for: match.range)
            else { continue }

            let tokenBounds = tokenSelection.bounds(for: page)
            guard tokenBounds.width > 0, tokenBounds.height > 0 else { continue }
            runLayouts.append((text: token, bounds: tokenBounds))
        }

        if !runLayouts.isEmpty {
            // Sort top-to-bottom then left-to-right (PDF Y grows upward, so descending
            // minY = top first). This matches PdfPig's NearestNeighbourWordExtractor
            // reading-order so that run-index keys align across platforms.
            return runLayouts.sorted { lhs, rhs in
                let yDelta = abs(lhs.bounds.midY - rhs.bounds.midY)
                if yDelta > 2.0 {
                    return lhs.bounds.midY > rhs.bounds.midY
                }
                return lhs.bounds.minX < rhs.bounds.minX
            }
        }

        // Fallback for PDFs where word-range selections cannot be resolved reliably.
        return pageLineLayouts(from: page)
    }

    private func pageLineLayouts(from page: PDFPage) -> [(text: String, bounds: CGRect)] {
        let cropBounds = page.bounds(for: .cropBox)
        guard cropBounds.width > 0, cropBounds.height > 0,
              let selection = page.selection(for: cropBounds)
        else { return [] }

        return selection
            .selectionsByLine()
            .compactMap { lineSelection in
                guard let raw = lineSelection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty
                else { return nil }

                let lineBounds = lineSelection.bounds(for: page)
                guard lineBounds.width > 0, lineBounds.height > 0 else { return nil }
                return (text: raw, bounds: lineBounds)
            }
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.bounds.minY - rhs.bounds.minY)
                if yDelta > 1.0 {
                    // PDF coordinates grow upward, so sort top-to-bottom.
                    return lhs.bounds.minY > rhs.bounds.minY
                }
                return lhs.bounds.minX < rhs.bounds.minX
            }
    }

    private func runLayout(for runIndex: Int, runLayouts: [(text: String, bounds: CGRect)]) -> (text: String, bounds: CGRect)? {
        if runIndex >= 0, runIndex < runLayouts.count {
            return runLayouts[runIndex]
        }
        if runIndex > 0, runIndex - 1 < runLayouts.count {
            return runLayouts[runIndex - 1]
        }
        return nil
    }

    private func resolvedFont(fontName: String, size: CGFloat, forceBold: Bool) -> UIFont {
        let trimmed = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let custom = UIFont(name: trimmed, size: size) {
            return custom
        }
        if forceBold {
            return .boldSystemFont(ofSize: size)
        }
        return .systemFont(ofSize: size)
    }

    final class Coordinator: NSObject {
        @Binding var currentPageIdx: Int
        var lastAutoCrop: Bool = false
        var lastOverrides: PdfOverridesPayload = .empty
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
