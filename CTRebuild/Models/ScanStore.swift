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

struct CatalogLinkCacheEntry: Codable, Identifiable, Equatable {
    var id: String
    var sourceCatalog: SourceCatalog
    var sourceItemId: String
    var sourceItemLabelSnapshot: String
    var scannedCode: String
    var linkCode: String
    var createdAtUtc: String
}

private struct PendingLinkWrite: Codable, Identifiable {
    var id: String
    var payload: CatalogLinkPayload
}

// MARK: - ScanStore

/// Shared source of truth for all assigned barcodes.
/// Persisted to ~/Documents/scan_records.json in the app sandbox.
final class ScanStore: ObservableObject {

    static let shared = ScanStore()

    @Published private(set) var records: [BarcodeRecord] = []
    @Published private(set) var catalogLinks: [CatalogLinkCacheEntry] = []
    @Published private(set) var activeTicketCatalog: SourceCatalog = .chaseTactical

    private let fileURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scan_records.json")
    }()

    private let linkFileURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog_links_cache.json")
    }()

    private let pendingWritesURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog_link_pending_writes.json")
    }()

    private var pendingWrites: [PendingLinkWrite] = []

    private init() {
        load()
        loadLinkCache()
        loadPendingWrites()
        loadActiveCatalogPreference()
    }

    // MARK: - Lookup

    func record(for barcode: String) -> BarcodeRecord? {
        records.first { $0.rawBarcode == barcode }
    }

    func catalogLink(for barcode: String) -> CatalogLinkCacheEntry? {
        catalogLinks.first { $0.scannedCode == barcode }
    }

    func isAssigned(barcode: String) -> Bool {
        record(for: barcode) != nil || catalogLink(for: barcode) != nil
    }

    func setActiveTicketCatalog(_ sourceCatalog: SourceCatalog) {
        activeTicketCatalog = sourceCatalog
        UserDefaults.standard.set(sourceCatalog.rawValue, forKey: "activeTicketCatalog")
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
        catalogLinks.removeAll { $0.scannedCode == record.rawBarcode }
        records.append(record)
        save()
        saveLinkCache()
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

    @MainActor
    func refreshLinksFromBackend() async {
        do {
            let remote = try await HubClient.shared.fetchCatalogLinks().map {
                CatalogLinkCacheEntry(
                    id: $0.id,
                    sourceCatalog: $0.sourceCatalog,
                    sourceItemId: $0.sourceItemId,
                    sourceItemLabelSnapshot: $0.sourceItemLabelSnapshot,
                    scannedCode: $0.scannedCode,
                    linkCode: $0.linkCode,
                    createdAtUtc: $0.createdAtUtc
                )
            }
            catalogLinks = remote
            saveLinkCache()
            await flushPendingWrites()
        } catch {
            // keep local cache when offline
        }
    }

    @MainActor
    func linkBarcodeToCatalog(scannedCode: String, item: CatalogSearchItem) async throws {
        let payload = CatalogLinkPayload(
            id: UUID().uuidString,
            sourceCatalog: item.sourceCatalog,
            sourceItemId: item.sourceItemId,
            sourceItemLabelSnapshot: "\(item.label) | \(item.subtitle)",
            scannedCode: scannedCode,
            linkCode: "",
            createdAtUtc: ISO8601DateFormatter().string(from: Date())
        )

        do {
            let saved = try await HubClient.shared.upsertCatalogLink(payload)
            upsertLocalLink(from: saved)
        } catch {
            enqueuePending(payload)
            upsertLocalCacheEntry(
                CatalogLinkCacheEntry(
                    id: payload.id,
                    sourceCatalog: payload.sourceCatalog,
                    sourceItemId: payload.sourceItemId,
                    sourceItemLabelSnapshot: payload.sourceItemLabelSnapshot,
                    scannedCode: payload.scannedCode,
                    linkCode: payload.linkCode.isEmpty ? "PENDING" : payload.linkCode,
                    createdAtUtc: payload.createdAtUtc
                )
            )
            throw error
        }
    }

    @MainActor
    func relinkCatalogEntry(_ link: CatalogLinkCacheEntry, to newBarcode: String) async throws {
        let payload = CatalogLinkPayload(
            id: UUID().uuidString,
            sourceCatalog: link.sourceCatalog,
            sourceItemId: link.sourceItemId,
            sourceItemLabelSnapshot: link.sourceItemLabelSnapshot,
            scannedCode: newBarcode,
            linkCode: "",
            createdAtUtc: ISO8601DateFormatter().string(from: Date())
        )

        do {
            try await HubClient.shared.deleteCatalogLink(id: link.id)
            let saved = try await HubClient.shared.upsertCatalogLink(payload)
            catalogLinks.removeAll { $0.id == link.id }
            upsertLocalLink(from: saved)
        } catch {
            enqueuePending(payload)
            throw error
        }
    }

    @MainActor
    func bootstrapLinkSync() async {
        await refreshLinksFromBackend()
        do {
            let context = try await HubClient.shared.fetchPdfContext()
            if let parsed = SourceCatalog(rawValue: context.sourceCatalog) {
                setActiveTicketCatalog(parsed)
            }
        } catch {
            // keep prior context if context fetch fails
        }
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

    private func loadLinkCache() {
        guard let data = try? Data(contentsOf: linkFileURL),
              let decoded = try? JSONDecoder().decode([CatalogLinkCacheEntry].self, from: data)
        else { return }
        catalogLinks = decoded
    }

    private func saveLinkCache() {
        guard let data = try? JSONEncoder().encode(catalogLinks) else { return }
        try? data.write(to: linkFileURL, options: .atomic)
    }

    private func loadPendingWrites() {
        guard let data = try? Data(contentsOf: pendingWritesURL),
              let decoded = try? JSONDecoder().decode([PendingLinkWrite].self, from: data)
        else { return }
        pendingWrites = decoded
    }

    private func savePendingWrites() {
        guard let data = try? JSONEncoder().encode(pendingWrites) else { return }
        try? data.write(to: pendingWritesURL, options: .atomic)
    }

    private func enqueuePending(_ payload: CatalogLinkPayload) {
        pendingWrites.append(PendingLinkWrite(id: UUID().uuidString, payload: payload))
        savePendingWrites()
    }

    @MainActor
    private func flushPendingWrites() async {
        guard !pendingWrites.isEmpty else { return }

        var remaining: [PendingLinkWrite] = []
        for pending in pendingWrites {
            do {
                let saved = try await HubClient.shared.upsertCatalogLink(pending.payload)
                upsertLocalLink(from: saved)
            } catch {
                remaining.append(pending)
            }
        }

        pendingWrites = remaining
        savePendingWrites()
    }

    private func upsertLocalLink(from record: CatalogLinkRecord) {
        upsertLocalCacheEntry(
            CatalogLinkCacheEntry(
                id: record.id,
                sourceCatalog: record.sourceCatalog,
                sourceItemId: record.sourceItemId,
                sourceItemLabelSnapshot: record.sourceItemLabelSnapshot,
                scannedCode: record.scannedCode,
                linkCode: record.linkCode,
                createdAtUtc: record.createdAtUtc
            )
        )
    }

    private func upsertLocalCacheEntry(_ entry: CatalogLinkCacheEntry) {
        catalogLinks.removeAll { $0.scannedCode == entry.scannedCode || $0.id == entry.id }
        catalogLinks.append(entry)
        saveLinkCache()
    }

    private func loadActiveCatalogPreference() {
        guard let raw = UserDefaults.standard.string(forKey: "activeTicketCatalog"),
              let catalog = SourceCatalog(rawValue: raw)
        else { return }
        activeTicketCatalog = catalog
    }
}
