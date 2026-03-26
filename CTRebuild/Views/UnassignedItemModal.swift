import SwiftUI

// Presented when the scanner sees a barcode the system has never seen before.
struct UnassignedItemModal: View {

    let rawBarcode: String
    var onDismiss: () -> Void

    // Form state
    @State private var classCode: String = "A"
    @State private var binLocation: String = ""
    @State private var quantity: Int = 0
    @State private var itemName: String = ""

    @State private var showValidationError = false
    @State private var selectedExistingId: String = ""
    @ObservedObject private var scanStore = ScanStore.shared

    private let classes = (65...90).map { String(UnicodeScalar($0)!) }  // A–Z

    private let binLocations: [String] = [
        "1-A-1A","1-A-1B","1-A-1C","1-A-1D","1-A-1E","1-A-1F",
        "1-A-2A","1-A-2B","1-A-2C","1-A-2D","1-A-2E","1-A-2F",
        "1-A-3A","1-A-3B","1-A-3C","1-A-3D","1-A-3E","1-A-3F",
        "1-A-4A","1-A-4B","1-A-4C","1-A-4D","1-A-4E","1-A-4F",
        "1-B-1A","1-B-1B","1-B-1C","1-B-1D","1-B-1E","1-B-1F",
        "1-B-2A","1-B-2B","1-B-2C","1-B-2D","1-B-2E","1-B-2F",
        "1-B-3A","1-B-3B","1-B-3C","1-B-3D","1-B-3E","1-B-3F",
        "1-B-4A","1-B-4B","1-B-4C","1-B-4D","1-B-4E","1-B-4F",
        "1-B-5A","1-B-5B","1-B-5C","1-B-5D","1-B-5E","1-B-5F",
        "1-B-6A","1-B-6B","1-B-6C","1-B-6D","1-B-6E","1-B-6F",
        "2-A-1A","2-A-1B","2-A-1C","2-A-1D","2-A-1E","2-A-1F",
        "2-A-2A","2-A-2B","2-A-2C","2-A-2D","2-A-2E","2-A-2F",
        "2-A-3A","2-A-3B","2-A-3C","2-A-3D","2-A-3E","2-A-3F",
        "2-A-4A","2-A-4B","2-A-4C","2-A-4D","2-A-4E","2-A-4F",
        "2-B-1A","2-B-1B","2-B-1C","2-B-1D","2-B-1E","2-B-1F",
        "2-B-2A","2-B-2B","2-B-2C","2-B-2D","2-B-2E","2-B-2F",
        "2-B-3A","2-B-3B","2-B-3C","2-B-3D","2-B-3E","2-B-3F",
        "2-B-4A","2-B-4B","2-B-4C","2-B-4D","2-B-4E","2-B-4F",
        "2-B-5A","2-B-5B","2-B-5C","2-B-5D","2-B-5E","2-B-5F",
        "2-B-6A","2-B-6B","2-B-6C","2-B-6D","2-B-6E","2-B-6F",
        "3-A-1A","3-A-1B","3-A-1C","3-A-1D","3-A-1E","3-A-1F",
        "3-A-2A","3-A-2B","3-A-2C","3-A-2D","3-A-2E","3-A-2F",
        "3-A-3A","3-A-3B","3-A-3C","3-A-3D","3-A-3E","3-A-3F",
        "3-A-4A","3-A-4B","3-A-4C","3-A-4D","3-A-4E","3-A-4F",
        "3-B-1A","3-B-1B","3-B-1C","3-B-1D","3-B-1E","3-B-1F",
        "3-B-2A","3-B-2B","3-B-2C","3-B-2D","3-B-2E","3-B-2F",
        "3-B-3A","3-B-3B","3-B-3C","3-B-3D","3-B-3E","3-B-3F",
        "3-B-4A","3-B-4B","3-B-4C","3-B-4D","3-B-4E","3-B-4F",
        "3-B-5A","3-B-5B","3-B-5C","3-B-5D","3-B-5E","3-B-5F",
        "3-B-6A","3-B-6B","3-B-6C","3-B-6D","3-B-6E","3-B-6F",
    ]

    // Live-generated QR code based on current class selection
    private var generatedQR: String {
        ScanStore.shared.nextQRCode(classCode: classCode)
    }


    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Raw barcode badge
                    Text(rawBarcode)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    // ── Class ─────────────────────────────────────────────────
                    fieldLabel("Class")
                    Menu {
                        ForEach(classes, id: \.self) { c in
                            Button(c) { classCode = c }
                        }
                    } label: {
                        HStack {
                            Text(classCode)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // ── Bin Location ──────────────────────────────────────────
                    fieldLabel("Bin Location")
                    Menu {
                        ForEach(binLocations, id: \.self) { bin in
                            Button(bin) { binLocation = bin }
                        }
                    } label: {
                        HStack {
                            Text(binLocation.isEmpty ? "Select Bin Location" : binLocation)
                                .foregroundColor(binLocation.isEmpty ? Color(.placeholderText) : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // ── Quantity ──────────────────────────────────────────────
                    fieldLabel("Quantity")
                    HStack(spacing: 12) {
                        Button {
                            if quantity > 0 { quantity -= 1 }
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 44, height: 44)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                        .foregroundColor(.primary)

                        Text("\(quantity)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 60)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .multilineTextAlignment(.center)

                        Button {
                            quantity += 1
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 44, height: 44)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                        .foregroundColor(.primary)
                    }

                    // ── Assigned QR Code (read-only, live) ────────────────────
                    fieldLabel("Assigned QR Code")
                    Text(generatedQR)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    // ── Item Name ──────────────────────────────────────────────
                    fieldLabel("Item Name")
                    TextField("Enter item name", text: $itemName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    // ── Divider ────────────────────────────────────────────────
                    Divider().padding(.vertical, 4)
                    Text("— Or Link to Existing Inventory Item —")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // ── Existing Item Picker ───────────────────────────────────
                    fieldLabel("Select Existing Item")
                    if scanStore.records.isEmpty {
                        Text("No assigned items yet.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Menu {
                            ForEach(scanStore.records) { record in
                                Button("\(record.id) \u00b7 \(record.itemName)") {
                                    selectedExistingId = record.id
                                }
                            }
                        } label: {
                            HStack {
                                if selectedExistingId.isEmpty {
                                    Text("\u2014 Select Item \u2014")
                                        .foregroundColor(Color(.placeholderText))
                                } else if let rec = scanStore.records.first(where: { $0.id == selectedExistingId }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rec.id)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Text(rec.itemName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // ── Link to inventory button ───────────────────────────────
                    Button {
                        applyInventoryLink()
                    } label: {
                        Text("Link Barcode to Selected Item")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
                    }

                    if showValidationError {
                        Text("Class and Bin Location are required.")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Unassigned Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Assign
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") { assign() }
                        .fontWeight(.semibold)
                }
                // Cancel
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.accentColor)
    }

    private func assign() {
        guard !classCode.isEmpty, !binLocation.isEmpty else {
            showValidationError = true
            return
        }
        let qr = generatedQR
        let record = BarcodeRecord(
            id: qr,
            rawBarcode: rawBarcode,
            classCode: classCode,
            binLocation: binLocation,
            itemName: itemName.isEmpty ? qr : itemName,
            quantity: quantity,
            linkedSpeedCell: nil,
            linkedToughHook: nil
        )
        ScanStore.shared.assign(record)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDismiss()
    }

    /// Links the scanned raw barcode to an existing assigned item.
    private func applyInventoryLink() {
        guard !selectedExistingId.isEmpty else { return }
        ScanStore.shared.relink(id: selectedExistingId, to: rawBarcode)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDismiss()
    }
}
