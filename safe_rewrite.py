import re

with open("CTRebuild/Views/PdfBrowserView.swift", "r", encoding="utf-8") as f:
    text = f.read()

# Make all edits strictly via exact string replacements or safe AST-like chops #

# 1. Remove ViewMode enum
text = text.replace("private enum ViewMode: String { case pdf, reader }\n\n", "")

# 2. Update PdfDetailView state vars (remove viewMode, autoCrop, overrides)
old_vars = """    @State private var displayDoc: PDFDocument
    @State private var soTitle: String = ""
    @State private var autoCropEnabled = true
    @AppStorage("pdfViewMode") private var viewMode: ViewMode = .pdf
    @State private var isPicked: Bool = false
    @State private var isShipped: Bool = false
    @State private var pdfOverrides: PdfOverridesPayload = .empty
    @AppStorage("panel_showMaterial") private var showMaterial = true"""
new_vars = """    @State private var displayDoc: PDFDocument
    @State private var soTitle: String = ""
    @State private var isPicked: Bool = false
    @State private var isShipped: Bool = false
    @AppStorage("panel_showMaterial") private var showMaterial = true"""
text = text.replace(old_vars, new_vars)

# 3. ZStack inside PdfDetailView body
old_zstack = """                ZStack {
                    if viewMode == .pdf {
                        PdfKitView(document: displayDoc, currentPageIdx: $currentPage,
                                   singlePage: true,
                                   autoCrop: autoCropEnabled,
                                   overrides: pdfOverrides)
                    } else {
                        NativeReaderView(document: displayDoc, filenames: filenames, singlePage: true)
                    }
                }"""
new_zstack = """                ZStack {
                    PdfKitView(document: displayDoc, currentPageIdx: $currentPage, singlePage: true)
                }"""
text = text.replace(old_zstack, new_zstack)

# 4. Remove all the bottom bar components that belonged to ViewMode / overrides
# But KEEP the bottom bar back button and the status toggles!
old_bottom_bar = """                    modeSegment(label: "PDF", active: viewMode == .pdf) {
                        viewMode = .pdf
                    }

                    modeSegment(label: "READER", active: viewMode == .reader) {
                        viewMode = .reader
                    }

                    Divider().frame(height: 20).opacity(0.2)

                    statusToggle(label: "PICKED", active: isPicked, activeColor: .orange) {
                        isPicked.toggle()
                        UserDefaults.standard.set(isPicked, forKey: "docpicked:\\(title)")
                    }

                    Divider().frame(height: 20).opacity(0.2)

                    statusToggle(label: "SHIPPED", active: isShipped, activeColor: .green) {
                        isShipped.toggle()
                        UserDefaults.standard.set(isShipped, forKey: "docshipped:\\(title)")
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
                    case .reader:
                        EmptyView()
                    }"""

new_bottom_bar = """                    statusToggle(label: "PICKED", active: isPicked, activeColor: .orange) {
                        isPicked.toggle()
                        UserDefaults.standard.set(isPicked, forKey: "docpicked:\\(title)")
                    }

                    Divider().frame(height: 20).opacity(0.2)

                    statusToggle(label: "SHIPPED", active: isShipped, activeColor: .green) {
                        isShipped.toggle()
                        UserDefaults.standard.set(isShipped, forKey: "docshipped:\\(title)")
                    }"""
text = text.replace(old_bottom_bar, new_bottom_bar)

# 5. Remove task overrides modifier from PdfDetailView
old_task = """.task(id: filenames.joined(separator: "|")) {
            await loadPdfOverrides()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task { await loadPdfOverrides() }
        }"""
text = text.replace(old_task, "")

# 6. Delete loadPdfOverrides and modeSegment from PdfDetailView
old_funcs_block = """    private func loadPdfOverrides() async {
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
                .background(active ? Color.white.opacity(0.88) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 2).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }"""
text = text.replace(old_funcs_block, "")

# 7. Completely strip Auto-Crop Helpers + all complex overlay formatting in PdfKitView.
# The remainder of the file after statusToggle:
# It's bounded as:
# MARK: - Auto-Crop Helpers
# (all the way to the end of the file)
# We will replace everything from MARK: - Auto-Crop Helpers down to the end of the file!

end_idx = text.find("// MARK: - Auto-Crop Helpers")
if end_idx != -1:
    text = text[:end_idx] + """// MARK: - PDFKit Wrapper

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

with open("CTRebuild/Views/PdfBrowserView.swift", "w", encoding="utf-8") as f:
    f.write(text)

print("Rewrite COMPLETE without regex botching bounds!")
