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
    @State private var speedCellSearch: String = ""
    @State private var toughHookSearch: String = ""
    @State private var selectedSpeedCell: String = ""
    @State private var selectedToughHook: String = ""
    @State private var showValidationError = false

    private let classes = (65...90).map { String(UnicodeScalar($0)!) }  // A–Z

    // Live-generated QR code based on current class selection
    private var generatedQR: String {
        ScanStore.shared.nextQRCode(classCode: classCode)
    }

    // Filtered picker lists (stubs — replaced by CT-Hub feed in a future phase)
    private var speedCellItems: [String] {
        let base = ["— Select Item —", "SC-001 · Hook Set A", "SC-002 · Carabiner Pack", "SC-003 · Utility Strap"]
        guard !speedCellSearch.isEmpty else { return base }
        return ["— Select Item —"] + base.dropFirst().filter { $0.localizedCaseInsensitiveContains(speedCellSearch) }
    }
    private var toughHookItems: [String] {
        let base = ["— Select Item —", "TH-001 · 1\" Hook", "TH-002 · 2\" Hook", "TH-003 · Heavy Duty 4\""]
        guard !toughHookSearch.isEmpty else { return base }
        return ["— Select Item —"] + base.dropFirst().filter { $0.localizedCaseInsensitiveContains(toughHookSearch) }
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
                    TextField("Select Bin Location", text: $binLocation)
                        .textInputAutocapitalization(.characters)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

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

                    // ── Speed Cell Items ───────────────────────────────────────
                    fieldLabel("Speed Cell Items")
                    TextField("Search speed cell...", text: $speedCellSearch)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    Picker("Speed Cell", selection: $selectedSpeedCell) {
                        ForEach(speedCellItems, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    // ── Tough Hook Items ───────────────────────────────────────
                    fieldLabel("Tough Hook Items")
                    TextField("Search tough hook...", text: $toughHookSearch)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    Picker("Tough Hook", selection: $selectedToughHook) {
                        ForEach(toughHookItems, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

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
            linkedSpeedCell: selectedSpeedCell.starts(with: "—") ? nil : selectedSpeedCell,
            linkedToughHook: selectedToughHook.starts(with: "—") ? nil : selectedToughHook
        )
        ScanStore.shared.assign(record)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDismiss()
    }

    /// Copies name + bin from the selected inventory item into the form fields.
    private func applyInventoryLink() {
        if !selectedSpeedCell.starts(with: "—") {
            itemName = selectedSpeedCell
        } else if !selectedToughHook.starts(with: "—") {
            itemName = selectedToughHook
        }
    }
}
