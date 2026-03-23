import SwiftUI
import PDFKit

// MARK: - PDF Browser View

struct PdfBrowserView: View {
    let safeArea: EdgeInsets

    @State private var files: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var openedFile: String? = nil
    @State private var pdfData: Data? = nil
    @State private var downloadingFile: String? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = pdfData, let filename = openedFile {
                // ── Inline PDF viewer — no sheet ──────────────────────────────
                PdfDetailView(
                    pdfData: data,
                    title: filename,
                    safeArea: safeArea,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            pdfData = nil
                            openedFile = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
            } else {
                // ── File list ─────────────────────────────────────────────────
                fileListContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: openedFile != nil)
        .task { await loadFiles() }
    }

    // MARK: - File list

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
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Retry") { Task { await loadFiles() } }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            } else if files.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No PDFs found")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("Select a folder in CT-Hub")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(files, id: \.self) { file in
                            PdfCardView(filename: file, isDownloading: downloadingFile == file)
                                .onTapGesture { Task { await openPdf(file) } }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeArea.bottom + 16)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        do {
            files = try await HubClient.shared.fetchPdfList()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openPdf(_ filename: String) async {
        downloadingFile = filename
        do {
            let data = try await HubClient.shared.fetchPdf(filename: filename)
            withAnimation(.easeInOut(duration: 0.22)) {
                pdfData = data
                openedFile = filename
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        downloadingFile = nil
    }
}

// MARK: - PDF Card

private struct PdfCardView: View {
    let filename: String
    let isDownloading: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(0.77, contentMode: .fit)
                if isDownloading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Text(filename)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - PDF Detail View (inline, slide-in, no sheet)

private struct PdfDetailView: View {
    let pdfData: Data
    let title: String
    let safeArea: EdgeInsets
    let onBack: () -> Void

    @State private var showTextMode = false

    /// Extracts selectable text from each page of the PDF.
    private var extractedText: String {
        guard let doc = PDFDocument(data: pdfData) else { return "Could not extract text." }
        var parts: [String] = []
        for i in 0..<doc.pageCount {
            if let text = doc.page(at: i)?.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("── Page \(i + 1) ──\n\(text)")
            }
        }
        return parts.isEmpty
            ? "No selectable text found in this PDF.\n\nThis PDF may be scanned images without embedded text."
            : parts.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Text(title)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // PDF / TEXT segment toggle
                HStack(spacing: 0) {
                    segmentButton(label: "PDF",  active: !showTextMode) { showTextMode = false }
                    segmentButton(label: "TEXT", active:  showTextMode) { showTextMode = true  }
                }
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.top, safeArea.top + 12)
            .padding(.bottom, 10)

            Divider().opacity(0.15)

            // ── Content ───────────────────────────────────────────────────────
            if showTextMode {
                ScrollView {
                    Text(extractedText)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .textSelection(.enabled)
                }
            } else {
                PdfKitView(data: pdfData)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func segmentButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? .black : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Color.white : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PDFKit UIViewRepresentable

private struct PdfKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
