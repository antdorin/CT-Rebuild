import SwiftUI
import PDFKit
import UIKit

// MARK: - Global overrides model (mirrors Hub override schema)

struct PdfGlobalOverrides: Equatable {
    var textSizeY:    Double = 1.75   // font size multiplier
    var forceBold:    Bool   = false
    var fontOverride: String = ""     // empty = system font
}

// MARK: - NativeReaderView

/// Native replacement for the WKWebView reader.
/// Fetches override settings from the Hub and renders extracted PDF text
/// in per-page cards styled with the global settings.
struct NativeReaderView: View {
    let document:   PDFDocument
    let filenames:  [String]
    var singlePage: Bool = false

    @State private var overrides = PdfGlobalOverrides()

    var body: some View {
        NativeReaderScrollable(document: document, overrides: overrides, singlePage: singlePage)
            .background(Color(uiColor: UIColor(white: 0.07, alpha: 1)))
            .task { await fetchOverrides() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )
            ) { _ in
                Task { await fetchOverrides() }
            }
    }

    // MARK: - Fetch overrides from Hub

    private func fetchOverrides() async {
        guard let filename = filenames.first else { return }

        let base = HubClient.shared.activeBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { return }

        let encoded = filename.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? filename
        guard let url = URL(string: "\(base)/api/pdf-overrides/\(encoded)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json   = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let global = json["global"] as? [String: Any]
            else { return }

            let newOverrides = PdfGlobalOverrides(
                textSizeY:    global["textSizeY"]    as? Double ?? 1.75,
                forceBold:    global["forceBold"]    as? Bool   ?? false,
                fontOverride: global["fontOverride"] as? String ?? ""
            )
            await MainActor.run { overrides = newOverrides }
        } catch {
            // Silently use defaults when Hub is unreachable
        }
    }
}

// MARK: - UIViewRepresentable bridge

private struct NativeReaderScrollable: UIViewRepresentable {
    let document:   PDFDocument
    let overrides:  PdfGlobalOverrides
    var singlePage: Bool = false

    func makeUIView(context: Context) -> NativeReaderHostView {
        NativeReaderHostView()
    }

    func updateUIView(_ view: NativeReaderHostView, context: Context) {
        view.configure(document: document, overrides: overrides, singlePage: singlePage)
    }
}

// MARK: - Scroll host

final class NativeReaderHostView: UIScrollView {

    private let stack       = UIStackView()
    private var lastDoc: PDFDocument? = nil
    private var lastOverrides   = PdfGlobalOverrides()
    private var lastSinglePage  = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 1)
        showsVerticalScrollIndicator   = true
        showsHorizontalScrollIndicator = false

        stack.axis    = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor,       constant: 14),
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor,   constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor,    constant: -14),
            stack.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor, constant: -28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(document: PDFDocument, overrides: PdfGlobalOverrides, singlePage: Bool = false) {
        let needsRebuild = document !== lastDoc || overrides != lastOverrides
        let modeChanged  = singlePage != lastSinglePage

        guard needsRebuild || modeChanged else { return }
        lastDoc        = document
        lastOverrides  = overrides
        lastSinglePage = singlePage

        // Single-page mode: snap to full-width pages horizontally, one per screen.
        // Continuous mode: vertical stack with a card per page.
        isPagingEnabled                    = singlePage
        stack.axis                         = singlePage ? .horizontal : .vertical
        showsHorizontalScrollIndicator     = singlePage
        showsVerticalScrollIndicator       = !singlePage

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for pageIdx in 0..<document.pageCount {
            guard let page = document.page(at: pageIdx) else { continue }
            let card = makePageCard(page: page, pageNumber: pageIdx + 1, overrides: overrides, singlePage: singlePage)
            stack.addArrangedSubview(card)
        }
    }

    private func makePageCard(page: PDFPage, pageNumber: Int, overrides: PdfGlobalOverrides, singlePage: Bool) -> UIView {
        let cropBox = page.bounds(for: .cropBox)
        let runs    = nrPageRunLayouts(from: page)

        let card = UIView()
        card.backgroundColor  = .white
        card.layer.cornerRadius = singlePage ? 0 : 10
        card.clipsToBounds    = true

        let canvas = NRCoordinatePageView(runs: runs, cropBox: cropBox, overrides: overrides)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(canvas)

        let pageLabel = UILabel()
        pageLabel.text          = "Page \(pageNumber)"
        pageLabel.font          = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pageLabel.textColor     = UIColor(white: 0.6, alpha: 1)
        pageLabel.textAlignment = .right
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(pageLabel)

        let aspectRatio = cropBox.width > 0 ? cropBox.height / cropBox.width : 1.4142
        card.translatesAutoresizingMaskIntoConstraints = false

        var constraints: [NSLayoutConstraint] = [
            canvas.topAnchor.constraint(equalTo: card.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            canvas.heightAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: aspectRatio),
            pageLabel.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 4),
            pageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            pageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            pageLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ]

        if singlePage {
            // In paging mode each card must be exactly one screen-width wide so that
            // UIScrollView.isPagingEnabled snaps one page per swipe.
            constraints += [
                card.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return card
    }
}

// MARK: - Coordinate-accurate page canvas

/// Positions each word token as a UILabel using its PDF-coordinate bounding box,
/// scaled proportionally to the view's rendered width. This bypasses the dual-layer
/// text rendering issue seen when PDFKit renders the raw document.
private final class NRCoordinatePageView: UIView {

    private let runs:      [(text: String, bounds: CGRect)]
    private let cropBox:   CGRect
    private let overrides: PdfGlobalOverrides
    private var lastLayoutWidth: CGFloat = 0

    init(runs: [(text: String, bounds: CGRect)], cropBox: CGRect, overrides: PdfGlobalOverrides) {
        self.runs      = runs
        self.cropBox   = cropBox
        self.overrides = overrides
        super.init(frame: .zero)
        backgroundColor = .white
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()

        let w = bounds.width
        guard w > 1, w != lastLayoutWidth, cropBox.width > 0 else { return }
        lastLayoutWidth = w

        subviews.forEach { $0.removeFromSuperview() }

        let scale = w / cropBox.width
        let pageH = cropBox.height * scale
        let sizeY = CGFloat(overrides.textSizeY)
        let bold  = overrides.forceBold
        let fName = overrides.fontOverride

        // Deduplicate runs that come from overlapping PDF text layers.
        // Two runs are considered duplicates when they share the same text and
        // their centre points are within 4 PDF-points of each other.
        let deduped = nrDeduplicatedRuns(runs)

        for run in deduped {
            // Convert PDF coords (bottom-left origin, Y increases upward)
            // to UIKit coords (top-left origin, Y increases downward).
            let runH = run.bounds.height * scale
            let runX = (run.bounds.minX - cropBox.minX) * scale
            let runY = pageH - ((run.bounds.maxY - cropBox.minY) * scale)

            let fontSize = max(8, runH * sizeY)
            let labelH   = fontSize * 1.35

            let label = UILabel()
            label.text          = run.text
            label.numberOfLines = 1
            label.textColor     = .black
            label.lineBreakMode = .byClipping

            if !fName.isEmpty, let f = UIFont(name: fName, size: fontSize) {
                label.font = f
            } else if bold {
                label.font = .boldSystemFont(ofSize: fontSize)
            } else {
                label.font = .systemFont(ofSize: fontSize)
            }

            // Size the label to its natural text width so it never truncates,
            // then pin its origin back to the PDF-coordinate position.
            label.sizeToFit()
            label.frame = CGRect(x: runX, y: runY,
                                 width: label.frame.width,
                                 height: max(label.frame.height, labelH))

            addSubview(label)
        }
    }
}

// MARK: - PDF run-layout extraction (mirrors PdfKitView.pageRunLayouts)

/// Removes duplicate word runs that arise from PDFs with two overlapping text layers.
/// Two runs are duplicates when they have the same text and their centre points
/// are within 4 PDF-points of each other.
private func nrDeduplicatedRuns(_ runs: [(text: String, bounds: CGRect)]) -> [(text: String, bounds: CGRect)] {
    var kept: [(text: String, bounds: CGRect)] = []
    for run in runs {
        let isDuplicate = kept.contains { existing in
            guard existing.text == run.text else { return false }
            let dx = abs(existing.bounds.midX - run.bounds.midX)
            let dy = abs(existing.bounds.midY - run.bounds.midY)
            return dx < 4 && dy < 4
        }
        if !isDuplicate { kept.append(run) }
    }
    return kept
}

private func nrPageRunLayouts(from page: PDFPage) -> [(text: String, bounds: CGRect)] {
    guard let rawText = page.string else { return [] }

    let nsText    = rawText as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    guard let wordRegex = try? NSRegularExpression(pattern: #"\S+"#) else {
        return nrPageLineLayouts(from: page)
    }

    var runLayouts: [(text: String, bounds: CGRect)] = []
    for match in wordRegex.matches(in: rawText, options: [], range: fullRange) {
        let token = nsText.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              let sel = page.selection(for: match.range) else { continue }
        let b = sel.bounds(for: page)
        guard b.width > 0, b.height > 0 else { continue }
        runLayouts.append((text: token, bounds: b))
    }

    if !runLayouts.isEmpty {
        return runLayouts.sorted { lhs, rhs in
            let yDelta = abs(lhs.bounds.midY - rhs.bounds.midY)
            if yDelta > 2.0 { return lhs.bounds.midY > rhs.bounds.midY }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }

    return nrPageLineLayouts(from: page)
}

private func nrPageLineLayouts(from page: PDFPage) -> [(text: String, bounds: CGRect)] {
    let cropBounds = page.bounds(for: .cropBox)
    guard cropBounds.width > 0, cropBounds.height > 0,
          let selection = page.selection(for: cropBounds) else { return [] }

    return selection
        .selectionsByLine()
        .compactMap { ls -> (text: String, bounds: CGRect)? in
            guard let raw = ls.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            let b = ls.bounds(for: page)
            guard b.width > 0, b.height > 0 else { return nil }
            return (text: raw, bounds: b)
        }
        .sorted { lhs, rhs in
            let yDelta = abs(lhs.bounds.minY - rhs.bounds.minY)
            if yDelta > 1.0 { return lhs.bounds.minY > rhs.bounds.minY }
            return lhs.bounds.minX < rhs.bounds.minX
        }
}
