import SwiftUI
import WebKit

// MARK: - Web Reader View
// Embeds a WKWebView loading documents.html (file list) from the Hub.
// Navigation within the site (documents → reader.html) stays in-page.

struct WebReaderView: UIViewRepresentable {
    let safeArea: EdgeInsets

    @ObservedObject private var client = HubClient.shared

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = wv
        load(wv)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        // Reload when the Hub URL changes or connection is established
        let base = client.activeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.coordinator.loadedBase != base {
            context.coordinator.loadedBase = base
            load(wv)
        }
    }

    private func load(_ wv: WKWebView) {
        let base = client.activeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let url = URL(string: base + "/documents.html") else {
            wv.loadHTMLString(offlineHTML, baseURL: nil)
            return
        }
        wv.load(URLRequest(url: url))
    }

    // MARK: - Coordinator

    class Coordinator {
        weak var webView: WKWebView?
        var loadedBase: String = ""
    }

    // MARK: - Offline placeholder

    private var offlineHTML: String {
        """
        <!DOCTYPE html><html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <style>
            body { margin:0; display:flex; align-items:center; justify-content:center;
                   height:100vh; background:#000; color:#888;
                   font-family:-apple-system,sans-serif; text-align:center; padding:24px; }
            .icon { font-size:48px; margin-bottom:16px; }
            p { font-size:15px; line-height:1.5; }
          </style>
        </head>
        <body>
          <div>
            <div class="icon">📄</div>
            <p>No Hub connected.<br>Set your Hub URL in App Settings.</p>
          </div>
        </body>
        </html>
        """
    }
}
