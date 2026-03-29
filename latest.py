import sys

with open("CTRebuild/Views/PdfBrowserView.swift", "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
skip = False
i = 0
while i < len(lines):
    line = lines[i]

    if "// MARK: - View Mode Enum" in line:
        i += 4
        continue
    
    if "@State private var autoCropEnabled" in line:
        i += 1
        continue
        
    if "private var viewMode: ViewMode" in line:
        i += 1
        continue
        
    if "private var pdfOverrides:" in line:
        i += 1
        continue

    if "if viewMode == .pdf {" in line:
        new_lines.append("                    PdfKitView(document: displayDoc, currentPageIdx: $currentPage, singlePage: true)\n")
        i += 8
        continue
        
    if "modeSegment(label: \"PDF\"" in line:
        i += 8
        continue
        
    if "switch viewMode {" in line:
        i += 14
        continue

    if ".task(id: filenames" in line:
        i += 10
        continue
        
    if "private func loadPdfOverrides() async {" in line:
        i += 12
        continue

    if "private func modeSegment(label:" in line:
        i += 11
        continue

    if "// MARK: - API / Overrides" in line:
        i += 2
        continue
        
    # Auto-Crop section is right after statusToggle.
    if "// MARK: - Auto-Crop Helpers" in line:
        # Break completely and insert our custom wrapper
        break

    new_lines.append(line)
    i += 1

clean_pdf_kit = """// MARK: - PDFKit Wrapper

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
            uiView.autoScales = true
            
            if let page = document.page(at: currentPageIdx) {
                uiView.go(to: page)
            }
        }
        
        let mode: PDFDisplayMode = singlePage ? .singlePage : .singlePageContinuous
        if uiView.displayMode != mode {
            uiView.displayMode = mode
            uiView.usePageViewController(singlePage)
        }
    }

    class Coordinator: NSObject {
        var binding: Binding<Int>
        private var isNavigating = false

        init(binding: Binding<Int>) {
            self.binding = binding
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !isNavigating, let view = notification.object as? PDFView,
                  let page = view.currentPage, let doc = view.document else { return }
            let idx = doc.index(for: page)
            isNavigating = true
            DispatchQueue.main.async {
                self.binding.wrappedValue = idx
                self.isNavigating = false
            }
        }
    }
}
"""

final_text = "".join(new_lines) + clean_pdf_kit

with open("CTRebuild/Views/PdfBrowserView.swift", "w", encoding="utf-8") as f:
    f.write(final_text)

