import SwiftUI

// Presented when the scanner sees a barcode the system already has a record for.
struct AssignedItemModal: View {

    let record: BarcodeRecord
    var onDismiss: () -> Void

    // Hold-to-delete state
    @State private var deleteProgress: CGFloat = 0
    @State private var isHoldingDelete = false
    @State private var deleteTimer: Timer? = nil

    // Relink state
    @State private var showRelinkEntry = false
    @State private var relinkBarcode: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── QR Code hero ──────────────────────────────────────────
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Text(record.id)
                                .font(.system(size: 44, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                            Text("System QR Code")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                    // ── Details grid ──────────────────────────────────────────
                    VStack(spacing: 0) {
                        detailRow(label: "Item Name",    value: record.itemName)
                        Divider().padding(.leading, 16)
                        detailRow(label: "Bin Location", value: record.binLocation)
                        Divider().padding(.leading, 16)
                        detailRow(label: "Class",        value: record.classCode)
                        Divider().padding(.leading, 16)
                        detailRow(label: "Quantity",     value: "\(record.quantity)")
                        if let sc = record.linkedSpeedCell {
                            Divider().padding(.leading, 16)
                            detailRow(label: "Speed Cell", value: sc)
                        }
                        if let th = record.linkedToughHook {
                            Divider().padding(.leading, 16)
                            detailRow(label: "Tough Hook", value: th)
                        }
                        Divider().padding(.leading, 16)
                        detailRow(label: "Raw Barcode",  value: record.rawBarcode)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                    // ── Relink ─────────────────────────────────────────────────
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
                                TextField("Scan or type barcode…", text: $relinkBarcode)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                Button("Save") {
                                    guard !relinkBarcode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                    ScanStore.shared.relink(id: record.id, to: relinkBarcode)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    onDismiss()
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

                    // ── Hold-to-delete ─────────────────────────────────────────
                    VStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.15))
                                .frame(height: 50)
                            // Fill bar
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.35))
                                .frame(width: deleteProgress * (UIScreen.main.bounds.width - 40), height: 50)
                                .animation(.linear(duration: 0.05), value: deleteProgress)
                            // Label
                            HStack {
                                Spacer()
                                Label(
                                    isHoldingDelete ? "Keep holding…" : "Hold 2s to Delete",
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
                                .onEnded   { _ in cancelDeleteHold() }
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
            .navigationTitle("Assigned Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

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

    // MARK: - Hold-to-delete logic

    private func startDeleteHold() {
        guard !isHoldingDelete else { return }
        isHoldingDelete = true
        deleteProgress  = 0

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

    private func commitDelete() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        ScanStore.shared.delete(id: record.id)
        isHoldingDelete = false
        onDismiss()
    }
}
