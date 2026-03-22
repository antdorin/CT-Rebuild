import Foundation

// MARK: - BarcodeRecord

struct BarcodeRecord: Codable, Identifiable, Equatable {
    var id: String           // System QR code, e.g. "A-001"
    var rawBarcode: String   // The original scanned string
    var classCode: String    // Single letter, e.g. "A"
    var binLocation: String  // e.g. "1A-1A"
    var itemName: String
    var quantity: Int
    var linkedSpeedCell: String?
    var linkedToughHook: String?
}

// MARK: - ScanStore

/// Shared source of truth for all assigned barcodes.
/// Persisted to ~/Documents/scan_records.json in the app sandbox.
final class ScanStore: ObservableObject {

    static let shared = ScanStore()

    @Published private(set) var records: [BarcodeRecord] = []

    private let fileURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scan_records.json")
    }()

    private init() { load() }

    // MARK: - Lookup

    func record(for barcode: String) -> BarcodeRecord? {
        records.first { $0.rawBarcode == barcode }
    }

    // MARK: - QR Code Generation

    /// Returns the next available QR code for the given class letter, e.g. "A-003".
    func nextQRCode(classCode: String) -> String {
        let prefix = String(classCode.uppercased().prefix(1))
        let existing = records
            .filter { $0.id.hasPrefix("\(prefix)-") }
            .compactMap { Int($0.id.dropFirst(2)) }
        let next = (existing.max() ?? 0) + 1
        return String(format: "\(prefix)-%03d", next)
    }

    // MARK: - Mutations

    func assign(_ record: BarcodeRecord) {
        records.removeAll { $0.rawBarcode == record.rawBarcode }
        records.append(record)
        save()
    }

    /// Re-points an existing QR code record to a different raw barcode.
    func relink(id: String, to newBarcode: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].rawBarcode = newBarcode
        save()
    }

    /// Permanently removes a record. The QR code is not returned to any pool.
    func delete(id: String) {
        records.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BarcodeRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
