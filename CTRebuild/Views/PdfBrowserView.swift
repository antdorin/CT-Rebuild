import SwiftUI
import PDFKit

// MARK: - PDF Browser View

struct PdfBrowserView: View {
    let safeArea: EdgeInsets

    @State private var files: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedFile: String? = nil
    @State private var pdfData: Data? = nil
    @State private var isViewerPresented = false
    @State private var isDownloading = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                Text("PDF VIEWER")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .tracking(4)
                    .padding(.top, safeArea.top + 16)
                    .padding(.bottom, 12)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
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
                                PdfCardView(filename: file, isDownloading: selectedFile == file && isDownloading)
                                    .onTapGesture {
                                        Task { await openPdf(file) }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, safeArea.bottom + 16)
                    }
                }
            }
        }
        .task { await loadFiles() }
        .sheet(isPresented: $isViewerPresented) {
            if let data = pdfData {
                PdfViewerView(pdfData: data, title: selectedFile ?? "Document")
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
        selectedFile = filename
        isDownloading = true
        do {
            pdfData = try await HubClient.shared.fetchPdf(filename: filename)
            isViewerPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isDownloading = false
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

// MARK: - PDF Viewer View

struct PdfViewerView: View {
    let pdfData: Data
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PdfKitView(data: pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
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
