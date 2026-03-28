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
    let document:  PDFDocument
    let filenames: [String]

    @State private var overrides = PdfGlobalOverrides()

    var body: some View {
        NativeReaderScrollable(document: document, overrides: overrides)
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
    let document:  PDFDocument
    let overrides: PdfGlobalOverrides

    func makeUIView(context: Context) -> NativeReaderHostView {
        NativeReaderHostView()
    }

    func updateUIView(_ view: NativeReaderHostView, context: Context) {
        view.configure(document: document, overrides: overrides)
    }
}

// MARK: - Scroll host

final class NativeReaderHostView: UIScrollView {

    private let stack         = UIStackView()
    private var lastPageCount = -1
    private var lastFontSize: CGFloat = -1
    private var lastBold      = false
    private var lastFontName  = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 1)

        stack.axis    = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor,      constant: 14),
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor,  constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor,   constant: -14),
            stack.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor, constant: -28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(document: PDFDocument, overrides: PdfGlobalOverrides) {
        let fontSize  = CGFloat(14.0 * overrides.textSizeY)
        let isBold    = overrides.forceBold
        let fontName  = overrides.fontOverride
        let pageCount = document.pageCount

        // Skip full rebuild when nothing changed
        let docChanged   = pageCount != lastPageCount
        let styleChanged = fontSize != lastFontSize || isBold != lastBold || fontName != lastFontName
        guard docChanged || styleChanged else { return }

        lastPageCount = pageCount
        lastFontSize  = fontSize
        lastBold      = isBold
        lastFontName  = fontName

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let font: UIFont
        if !fontName.isEmpty, let named = UIFont(name: fontName, size: fontSize) {
            font = named
        } else if isBold {
            font = .boldSystemFont(ofSize: fontSize)
        } else {
            font = .systemFont(ofSize: fontSize)
        }

        for pageIdx in 0..<pageCount {
            guard let page = document.page(at: pageIdx),
                  let raw  = page.string else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            stack.addArrangedSubview(makePageCard(text: text, font: font, pageNumber: pageIdx + 1))
        }
    }

    private func makePageCard(text: String, font: UIFont, pageNumber: Int) -> UIView {
        let card = UIView()
        card.backgroundColor  = .white
        card.layer.cornerRadius = 10
        card.clipsToBounds    = true

        let tv = UITextView()
        tv.isEditable         = false
        tv.isScrollEnabled    = false
        tv.backgroundColor    = .clear
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 8, right: 12)
        tv.font               = font
        tv.textColor          = .black
        tv.text               = text
        tv.translatesAutoresizingMaskIntoConstraints = false

        let pageLabel = UILabel()
        pageLabel.text          = "Page \(pageNumber)"
        pageLabel.font          = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pageLabel.textColor     = UIColor(white: 0.6, alpha: 1)
        pageLabel.textAlignment = .right
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(tv)
        card.addSubview(pageLabel)

        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: card.topAnchor),
            tv.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            pageLabel.topAnchor.constraint(equalTo: tv.bottomAnchor),
            pageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            pageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            pageLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])

        return card
    }
}
