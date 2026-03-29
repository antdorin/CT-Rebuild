import SwiftUI
import PDFKit
import UIKit

// MARK: - Global overrides model (mirrors Hub override schema)

struct PdfGlobalOverrides: Equatable {
    var textSizeY:    Double = 1.75   // font size multiplier
    var textSizeX:    Double = 1.0    // horizontal text width scale
    var pageZoomX:    Double = 1.0    // zoom from crop centre (X)
    var pageZoomY:    Double = 1.0    // zoom from crop centre (Y)
    var pageSizeX:    Double = 1.0    // position scale from crop edge (X)
    var pageSizeY:    Double = 1.0    // position scale from crop edge (Y)
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

    @State private var overrides   = PdfGlobalOverrides()
    @State private var hubWordDoc: HubWordDocument? = nil

    var body: some View {
        NativeReaderScrollable(
            document: document,
            overrides: overrides,
            hubWordDoc: hubWordDoc,
            singlePage: singlePage
        )
        .background(Color(uiColor: UIColor(white: 0.07, alpha: 1)))
        .task { await fetchFromHub() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task { await fetchFromHub() }
        }
    }

    // MARK: - Fetch overrides + word layout from Hub (parallel)

    private func fetchFromHub() async {
        guard let filename = filenames.first else { return }
        async let overridesTask  = HubClient.shared.fetchPdfOverrides(filename: filename)
        async let wordLayoutTask = HubClient.shared.fetchPdfWords(filename: filename)

        // Overrides
        if let payload = try? await overridesTask {
            let fallback = PdfGlobalOverrides()
            let rawSizeY = payload.hasEdits ? payload.global.textSizeY : fallback.textSizeY
            let newOverrides = PdfGlobalOverrides(
                textSizeY:    min(2.0, max(0.75, rawSizeY)),
                textSizeX:    max(0.4, payload.global.textSizeX),
                pageZoomX:    max(0.1, payload.global.pageZoomX),
                pageZoomY:    max(0.1, payload.global.pageZoomY),
                pageSizeX:    max(0.1, payload.global.pageSizeX),
                pageSizeY:    max(0.1, payload.global.pageSizeY),
                forceBold:    payload.global.forceBold,
                fontOverride: payload.global.fontOverride
            )
            await MainActor.run { overrides = newOverrides }
        }

        // Word layout — nil when Hub is unreachable; iOS falls back to PDFKit extraction.
        let wordDoc = try? await wordLayoutTask
        await MainActor.run { hubWordDoc = wordDoc }
    }
}

// MARK: - UIViewRepresentable bridge

private struct NativeReaderScrollable: UIViewRepresentable {
    let document:   PDFDocument
    let overrides:  PdfGlobalOverrides
    let hubWordDoc: HubWordDocument?
    var singlePage: Bool = false

    func makeUIView(context: Context) -> NativeReaderHostView {
        NativeReaderHostView()
    }

    func updateUIView(_ view: NativeReaderHostView, context: Context) {
        view.configure(document: document, overrides: overrides,
                       hubWordDoc: hubWordDoc, singlePage: singlePage)
    }
}

// MARK: - Scroll host

final class NativeReaderHostView: UIScrollView {

    private let stack           = UIStackView()
    private var lastDoc: PDFDocument? = nil
    private var lastOverrides   = PdfGlobalOverrides()
    private var lastHubWordDoc: HubWordDocument? = nil
    private var lastSinglePage  = false

    // Mutable constraints swapped between continuous/paged layouts.
    private var stackPadConstraints: [NSLayoutConstraint] = []
    private var stackWidthConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 1)
        showsVerticalScrollIndicator   = true
        showsHorizontalScrollIndicator = false

        stack.axis    = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Fixed edges — always pinned edge-to-edge on content guide.
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])

        // Width constraint — starts with continuous padding, updated on mode change.
        stackWidthConstraint = stack.widthAnchor.constraint(
            equalTo: frameLayoutGuide.widthAnchor, constant: -28)
        stackWidthConstraint.isActive = true

        // Padding constraints for continuous mode.
        stackPadConstraints = [
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -14),
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(document: PDFDocument, overrides: PdfGlobalOverrides,
                   hubWordDoc: HubWordDocument?, singlePage: Bool = false) {
        // Rebuild when Hub word data arrives (hubWordDoc nil→value transition counts as a change).
        let wordDocChanged = (hubWordDoc == nil) != (lastHubWordDoc == nil)
            || (hubWordDoc?.pages.count != lastHubWordDoc?.pages.count)
        let needsRebuild = document !== lastDoc || overrides != lastOverrides || wordDocChanged
        let modeChanged  = singlePage != lastSinglePage

        guard needsRebuild || modeChanged else { return }
        lastDoc        = document
        lastOverrides  = overrides
        lastHubWordDoc = hubWordDoc
        lastSinglePage = singlePage

        if singlePage {
            // Full-page vertical paging: zero spacing, zero insets, snap one page per swipe.
            stack.axis    = .vertical
            stack.spacing = 0
            isPagingEnabled = true
            showsVerticalScrollIndicator   = false
            showsHorizontalScrollIndicator = false
            stackPadConstraints.forEach { $0.isActive = false }
            stackWidthConstraint.constant = 0   // full width
        } else {
            // Continuous scroll: vertical with margins.
            stack.axis    = .vertical
            stack.spacing = 14
            isPagingEnabled = false
            showsVerticalScrollIndicator   = true
            showsHorizontalScrollIndicator = false
            stackPadConstraints.forEach { $0.isActive = true }
            stackWidthConstraint.constant = -28
        }

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for pageIdx in 0..<document.pageCount {
            guard let page = document.page(at: pageIdx) else { continue }
            // 1-based page number, but Hub pages array is also 1-based from PdfPig.
            let hubPage = lastHubWordDoc?.pages.first { $0.page == pageIdx + 1 }
            let card = makePageCard(page: page, pageNumber: pageIdx + 1,
                                    hubPage: hubPage, overrides: overrides, singlePage: singlePage)
            stack.addArrangedSubview(card)
        }
    }

    private func makePageCard(page: PDFPage, pageNumber: Int,
                               hubPage: HubPageWords?, overrides: PdfGlobalOverrides,
                               singlePage: Bool) -> UIView {
        let cropBox = page.bounds(for: .cropBox)
        let runs: [NRTextRun] = hubPage.map { hp in
            hp.words.map { w in
                NRTextRun(
                    text: w.text,
                    bounds: CGRect(x: w.x0, y: w.y0,
                                   width: w.x1 - w.x0, height: w.y1 - w.y0),
                    originalFontHeight: w.y1 - w.y0
                )
            }
        } ?? []

        let card = UIView()
        card.backgroundColor  = UIColor(white: 0.07, alpha: 1)
        card.clipsToBounds    = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let canvas = NRCoordinatePageView(runs: runs, cropBox: cropBox, overrides: overrides)
        canvas.layer.cornerRadius = singlePage ? 0 : 10
        canvas.clipsToBounds      = true
        canvas.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(canvas)

        let pageLabel = UILabel()
        pageLabel.text          = "\(pageNumber) / \(page.document?.pageCount ?? 0)"
        pageLabel.font          = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pageLabel.textColor     = UIColor(white: 0.9, alpha: 0.55)
        pageLabel.textAlignment = .right
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(pageLabel)

        let aspectRatio = cropBox.width > 0 ? cropBox.height / cropBox.width : 1.4142

        var constraints: [NSLayoutConstraint]

        if singlePage {
            // Full-page mode: card fills the viewport exactly.
            // Canvas is aspect-fit centred inside the card — text never clips on
            // landscape screens and always fills portrait screens edge-to-edge.
            let canvasWidth  = canvas.widthAnchor.constraint(equalTo: card.widthAnchor)
            canvasWidth.priority = .defaultHigh

            constraints = [
                // Card = one full viewport page (drives vertical paging snap).
                card.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
                card.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
                // Canvas: centred, aspect-fit.
                canvas.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                canvas.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                canvas.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor),
                canvas.heightAnchor.constraint(lessThanOrEqualTo: card.heightAnchor),
                canvas.heightAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: aspectRatio),
                canvasWidth,
                // Page indicator overlay — bottom-right corner.
                pageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                pageLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            ]
        } else {
            // Continuous scroll mode: card sized to page aspect ratio with rounded corners.
            card.backgroundColor = .white
            canvas.layer.cornerRadius = 10
            constraints = [
                canvas.topAnchor.constraint(equalTo: card.topAnchor),
                canvas.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                canvas.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                canvas.heightAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: aspectRatio),
                pageLabel.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 4),
                pageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                pageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
                pageLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return card
    }
}

// MARK: - Word run model

/// A single extracted word token with its PDF-space bounding box.
private struct NRTextRun {
    let text:               String
    let bounds:             CGRect  // PDF-space: bottom-left origin, Y increases upward
    let originalFontHeight: CGFloat // bounds.height in PDF points
}

// MARK: - Coordinate-accurate page canvas

/// Positions each word token as a UILabel using its PDF-coordinate bounding box,
/// scaled proportionally to the view's rendered width. This bypasses the dual-layer
/// text rendering issue seen when PDFKit renders the raw document.
private final class NRCoordinatePageView: UIView {

    private let runs:      [NRTextRun]
    private let cropBox:   CGRect
    private let overrides: PdfGlobalOverrides
    private var lastLayoutWidth: CGFloat = 0

    init(runs: [NRTextRun], cropBox: CGRect, overrides: PdfGlobalOverrides) {
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

        let sizeY = CGFloat(overrides.textSizeY)
        let sizeX = CGFloat(overrides.textSizeX)
        let zoomX = CGFloat(overrides.pageZoomX)
        let zoomY = CGFloat(overrides.pageZoomY)
        let pSclX = CGFloat(overrides.pageSizeX)
        let pSclY = CGFloat(overrides.pageSizeY)
        let bold  = overrides.forceBold
        let fName = overrides.fontOverride

        // Build an authoritative CGAffineTransform that maps PDF-space
        // (bottom-left origin, Y increases upward) to UIKit view-space
        // (top-left origin, Y increases downward), scaled to fit cropBox in bounds.
        // Using a transform matrix handles non-zero CropBox origins automatically
        // and eliminates the manual runY = pageH - ... drift-prone calculation.
        //   x' = (px - cropBox.minX) * scale
        //   y' = (cropBox.maxY  - py) * scale
        let scale = w / cropBox.width
        let baseTransform = CGAffineTransform(
            a: scale,  b: 0,
            c: 0,      d: -scale,
            tx: -cropBox.minX * scale,
            ty: (cropBox.minY + cropBox.height) * scale
        )

        let deduped = nrDeduplicatedRuns(runs)

        for run in deduped {
            // Apply overrides in PDF space (mirrors Hub annotation path):
            // 1. Zoom from crop centre.
            let zMinX = (run.bounds.minX - cropBox.midX) * zoomX + cropBox.midX
            let zMinY = (run.bounds.minY - cropBox.midY) * zoomY + cropBox.midY
            let zoomedRect = CGRect(x: zMinX, y: zMinY,
                                    width:  run.bounds.width  * zoomX,
                                    height: run.bounds.height * zoomY)
            // 2. Position scale from crop edge.
            let adjMinX = cropBox.minX + (zoomedRect.minX - cropBox.minX) * pSclX
            let adjMinY = cropBox.minY + (zoomedRect.minY - cropBox.minY) * pSclY
            let adjRect = CGRect(x: adjMinX, y: adjMinY,
                                 width: zoomedRect.width, height: zoomedRect.height)

            // 3. Apply the authoritative transform.
            //    CGRect.applying returns the smallest enclosing rect of all
            //    4 transformed corners, so the Y-flip produces a correct
            //    positive-height rect with origin at the UIKit top edge.
            let uiRect = adjRect.applying(baseTransform)

            let fontSize = max(8, uiRect.height * sizeY)
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
            // Apply textSizeX to scale the label width (matches Hub horizontal scale control).
            label.sizeToFit()
            label.frame = CGRect(x: uiRect.minX, y: uiRect.minY,
                                 width: label.frame.width * sizeX,
                                 height: max(label.frame.height, labelH))

            addSubview(label)
        }
    }
}

// MARK: - PDF run-layout extraction (mirrors PdfKitView.pageRunLayouts)

/// Returns true when two runs are considered the same word from overlapping text layers.
/// Uses a dynamic tolerance based on line height rather than fixed magic numbers,
/// making the check robust across font sizes and OCR resolutions.
private func nrRunsAreDuplicate(_ a: NRTextRun, _ b: NRTextRun) -> Bool {
    guard a.text.lowercased() == b.text.lowercased() else { return false }
    let tolerance = max(a.bounds.height, b.bounds.height) * 0.5
    return abs(a.bounds.midX - b.bounds.midX) < tolerance &&
           abs(a.bounds.midY - b.bounds.midY) < tolerance
}

/// Removes duplicate word runs that arise from PDFs with two overlapping text layers.
/// Uses a spatial hash so each run is compared only against the ~9 nearby grid cells
/// instead of the entire list, reducing complexity from O(n²) to near O(n).
private func nrDeduplicatedRuns(_ runs: [NRTextRun]) -> [NRTextRun] {
    let gridSize: CGFloat = 25.0
    var spatialMap = [String: [NRTextRun]]()
    var unique     = [NRTextRun]()

    for run in runs {
        let gx = Int(run.bounds.midX / gridSize)
        let gy = Int(run.bounds.midY / gridSize)

        var isDup = false
        outer: for dx in -1...1 {
            for dy in -1...1 {
                let key = "\(gx + dx),\(gy + dy)"
                guard let candidates = spatialMap[key] else { continue }
                for existing in candidates where nrRunsAreDuplicate(run, existing) {
                    isDup = true
                    break outer
                }
            }
        }

        if !isDup {
            unique.append(run)
            let key = "\(gx),\(gy)"
            spatialMap[key, default: []].append(run)
        }
    }
    return unique
}
