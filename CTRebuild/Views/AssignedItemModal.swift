import SwiftUI

// Presented when a scanned barcode already resolves to an assignment.
struct AssignedItemModal: View {

    let record: BarcodeRecord?
    let catalogLink: CatalogLinkCacheEntry?
    var onDismiss: () -> Void

    // Hold-to-delete state
    @State private var deleteProgress: CGFloat = 0
    @State private var isHoldingDelete = false
    @State private var deleteTimer: Timer? = nil

    // Relink state
    @State private var showRelinkEntry = false
    @State private var relinkBarcode: String = ""

    private var titleText: String {
        record != nil ? "Assigned Item" : "Linked Catalog Item"
    }

    private var heroCode: String {
        if let record { return record.id }
        return catalogLink?.linkCode ?? "LINK"
    }

    private var scannedBarcode: String {
        if let record { return record.rawBarcode }
        return catalogLink?.scannedCode ?? ""
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Text(heroCode)
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                            Text(record != nil ? "System QR Code" : "Catalog Link")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                    VStack(spacing: 0) {
                        if let record {
                            detailRow(label: "Item Name", value: record.itemName)
                            Divider().padding(.leading, 16)
                            detailRow(label: "Bin Location", value: record.binLocation)
                            Divider().padding(.leading, 16)
                            detailRow(label: "Class", value: record.classCode)
                            Divider().padding(.leading, 16)
                            detailRow(label: "Quantity", value: "\(record.quantity)")
                            if let sc = record.linkedSpeedCell {
                                Divider().padding(.leading, 16)
                                detailRow(label: "Speed Cell", value: sc)
                            }
                            if let th = record.linkedToughHook {
                                Divider().padding(.leading, 16)
                                detailRow(label: "Tough Hook", value: th)
                            }
                        }

                        if let link = catalogLink {
                            detailRow(label: "Source", value: link.sourceCatalog.displayName)
                            Divider().padding(.leading, 16)
                            detailRow(label: "Catalog Item", value: link.sourceItemLabelSnapshot)
                                .lineLimit(2)
                            Divider().padding(.leading, 16)
                            detailRow(label: "Source Item ID", value: link.sourceItemId)
                                .font(.system(size: 11, design: .monospaced))
                        }

                        Divider().padding(.leading, 16)
                        detailRow(label: "Raw Barcode", value: scannedBarcode)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                    Button {
                        withAnimation { showRelinkEntry.toggle() }
                    } label: {
                        Label(showRelinkEntry ? "Cancel Relink" : "Relink to Different Barcode",
                              systemImage: showRelinkEntry ? "xmark" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                    }

                    if showRelinkEntry {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enter new barcode value")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack(spacing: 10) {
                                TextField("Scan or type barcode...", text: $relinkBarcode)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                Button("Save") {
                                    Task {
                                        await saveRelink()
                                    }
                                }
                                .disabled(relinkBarcode.trimmingCharacters(in: .whitespaces).isEmpty)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundColor(.white)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.15))
                                .frame(height: 50)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.35))
                                .frame(width: deleteProgress * (UIScreen.main.bounds.width - 40), height: 50)
                                .animation(.linear(duration: 0.05), value: deleteProgress)
                            HStack {
                                Spacer()
                                Label(
                                    isHoldingDelete ? "Keep holding..." : "Hold 2s to Delete",
                                    systemImage: "trash"
                                )
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.red)
                                Spacer()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in startDeleteHold() }
                                .onEnded { _ in cancelDeleteHold() }
                        )

                        Text("Record will be permanently deleted. This cannot be undone.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func startDeleteHold() {
        guard !isHoldingDelete else { return }
        isHoldingDelete = true
        deleteProgress = 0

        let start = Date()
        let duration: TimeInterval = 2.0

        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(start)
            deleteProgress = CGFloat(min(elapsed / duration, 1.0))

            if elapsed >= duration {
                timer.invalidate()
                commitDelete()
            }
        }
    }

    private func cancelDeleteHold() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        withAnimation { deleteProgress = 0 }
        isHoldingDelete = false
    }

    @MainActor
    private func saveRelink() async {
        let trimmed = relinkBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let record {
            ScanStore.shared.relink(id: record.id, to: trimmed)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDismiss()
            return
        }

        if let catalogLink {
            do {
                try await ScanStore.shared.relinkCatalogEntry(catalogLink, to: trimmed)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDismiss()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                onDismiss()
            }
        }
    }

    private func commitDelete() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        if let record {
            ScanStore.shared.delete(id: record.id)
        }
        if let catalogLink {
            Task {
                try? await HubClient.shared.deleteCatalogLink(id: catalogLink.id)
                await ScanStore.shared.refreshLinksFromBackend()
            }
        }
        isHoldingDelete = false
        onDismiss()
    }
}
