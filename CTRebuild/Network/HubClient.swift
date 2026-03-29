import Foundation
import Combine

// MARK: - Models

/// PDF file metadata returned by /api/pdfs/meta
struct PdfMeta: Decodable {
    let name: String
    let modified: String   // UTC ISO 8601, e.g. "2024-01-15T10:30:00.0000000Z"
    let sourceCatalog: String?

// MARK: - Word layout models (returned by /api/pdf-words/{filename})

/// One word token with its PDF-space bounding box.
/// Coordinates are bottom-left origin, Y increases upward (raw PDF space).
struct HubWordBox: Decodable {
    let text: String
    let x0: Double
    let y0: Double
    let x1: Double
    let y1: Double
}

struct HubPageWords: Decodable {
    let page:   Int
    let width:  Double
    let height: Double
    let words:  [HubWordBox]
}

struct HubWordDocument: Decodable {
    let pages: [HubPageWords]
}

    init(name: String, modified: String, sourceCatalog: String? = nil) {
        self.name = name
        self.modified = modified
        self.sourceCatalog = sourceCatalog
    }
}

struct PdfContext: Decodable {
    let sourceCatalog: String
}

struct PdfOverrideGlobal: Codable, Equatable {
    var textSizeY: Double
    var textSizeX: Double
    var pageZoomX: Double
    var pageZoomY: Double
    var pageSizeX: Double
    var pageSizeY: Double
    var forceBold: Bool
    var fontOverride: String

    static let defaults = PdfOverrideGlobal(
        textSizeY: 1.75,
        textSizeX: 1.0,
        pageZoomX: 1.0,
        pageZoomY: 1.0,
        pageSizeX: 1.0,
        pageSizeY: 1.0,
        forceBold: false,
        fontOverride: ""
    )

    init(
        textSizeY: Double = 1.75,
        textSizeX: Double = 1.0,
        pageZoomX: Double = 1.0,
        pageZoomY: Double = 1.0,
        pageSizeX: Double = 1.0,
        pageSizeY: Double = 1.0,
        forceBold: Bool = false,
        fontOverride: String = ""
    ) {
        self.textSizeY = textSizeY
        self.textSizeX = textSizeX
        self.pageZoomX = pageZoomX
        self.pageZoomY = pageZoomY
        self.pageSizeX = pageSizeX
        self.pageSizeY = pageSizeY
        self.forceBold = forceBold
        self.fontOverride = fontOverride
    }

    enum CodingKeys: String, CodingKey {
        case textSizeY, textSizeX, pageZoomX, pageZoomY, pageSizeX, pageSizeY, forceBold, fontOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textSizeY = try container.decodeIfPresent(Double.self, forKey: .textSizeY) ?? 1.75
        textSizeX = try container.decodeIfPresent(Double.self, forKey: .textSizeX) ?? 1.0
        pageZoomX = try container.decodeIfPresent(Double.self, forKey: .pageZoomX) ?? 1.0
        pageZoomY = try container.decodeIfPresent(Double.self, forKey: .pageZoomY) ?? 1.0
        pageSizeX = try container.decodeIfPresent(Double.self, forKey: .pageSizeX) ?? 1.0
        pageSizeY = try container.decodeIfPresent(Double.self, forKey: .pageSizeY) ?? 1.0
        forceBold = try container.decodeIfPresent(Bool.self, forKey: .forceBold) ?? false
        fontOverride = try container.decodeIfPresent(String.self, forKey: .fontOverride) ?? ""
    }
}

struct PdfRunOverride: Codable, Equatable {
    var dx: Double
    var dy: Double
    var sizeScale: Double

    init(dx: Double = 0, dy: Double = 0, sizeScale: Double = 1.0) {
        self.dx = dx
        self.dy = dy
        self.sizeScale = sizeScale
    }

    enum CodingKeys: String, CodingKey {
        case dx, dy, sizeScale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dx = try container.decodeIfPresent(Double.self, forKey: .dx) ?? 0
        dy = try container.decodeIfPresent(Double.self, forKey: .dy) ?? 0
        sizeScale = try container.decodeIfPresent(Double.self, forKey: .sizeScale) ?? 1.0
    }
}

struct PdfOverridesPayload: Codable, Equatable {
    var global: PdfOverrideGlobal
    var runs: [String: PdfRunOverride]

    static let empty = PdfOverridesPayload()

    var hasEdits: Bool {
        !runs.isEmpty || global != .defaults
    }

    init(global: PdfOverrideGlobal = .defaults, runs: [String: PdfRunOverride] = [:]) {
        self.global = global
        self.runs = runs
    }

    enum CodingKeys: String, CodingKey {
        case global, runs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        global = try container.decodeIfPresent(PdfOverrideGlobal.self, forKey: .global) ?? .defaults
        runs = try container.decodeIfPresent([String: PdfRunOverride].self, forKey: .runs) ?? [:]
    }
}

enum SourceCatalog: String, Codable, CaseIterable, Identifiable {
    case chaseTactical = "chase_tactical"
    case toughHook = "tough_hook"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chaseTactical: return "Chase Tactical"
        case .toughHook: return "Tough Hook"
        }
    }
}

struct CatalogLinkRecord: Codable, Identifiable {
    let id: String
    let sourceCatalog: SourceCatalog
    let sourceItemId: String
    let sourceItemLabelSnapshot: String
    let scannedCode: String
    let linkCode: String
    let createdAtUtc: String
}

struct CatalogLinkPayload: Codable {
    let id: String
    let sourceCatalog: SourceCatalog
    let sourceItemId: String
    let sourceItemLabelSnapshot: String
    let scannedCode: String
    let linkCode: String
    let createdAtUtc: String
}

struct ChaseCatalogItem: Decodable, Identifiable {
    let id: String
    let bin: String
    let className: String
    let classLetter: String
    let classId: String
    let label: String
    let qty: Int
    let notes: String

    enum CodingKeys: String, CodingKey {
        case id
        case bin
        case className
        case classLetter
        case classId = "class"
        case label
        case qty
        case notes
    }
}

struct ToughHookCatalogItem: Decodable, Identifiable {
    let id: String
    let bin: String
    let sku: String
    let description: String
    let qty: Int
}

struct CatalogSearchItem: Identifiable {
    let sourceCatalog: SourceCatalog
    let sourceItemId: String
    let label: String
    let subtitle: String
    let bin: String

    var id: String { "\(sourceCatalog.rawValue):\(sourceItemId)" }
}

// MARK: - Hub Client

/// HTTP + WebSocket client for CT-Hub.
/// Call `connect()` after setting the active URL — or it is called automatically
/// when `setActiveUrl` is used. Reconnects with exponential backoff on drop.
final class HubClient: ObservableObject {
    static let shared = HubClient()
    private init() {}

    // Key used to store the active IP in UserDefaults
    static let activeUrlKey = "hubActiveUrl"
    static let savedUrlsKey = "hubSavedUrls"

    // MARK: - Connection state (observable)
    @Published private(set) var isConnected: Bool = false
    /// Human-readable status shown in Hub Settings for real-time diagnostics.
    @Published private(set) var connectionDiag: String = ""

    private var wsTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 2
    private let maxDelay: TimeInterval = 30

    var activeBaseURL: String {
        UserDefaults.standard.string(forKey: HubClient.activeUrlKey) ?? ""
    }

    // MARK: - WebSocket lifecycle

    /// Opens (or re-opens) a WebSocket to the active hub URL.
    /// First runs an HTTP preflight to verify basic reachability, then opens WS.
    func connect() {
        reconnectTask?.cancel()
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        isConnected = false

        let base = activeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty,
              let httpURL = URL(string: base),
              var comps = URLComponents(url: httpURL, resolvingAgainstBaseURL: false)
        else { return }

        // ── HTTP preflight: test basic reachability before WebSocket ────────
        DispatchQueue.main.async { self.connectionDiag = "Testing HTTP to \(httpURL.host ?? "?")…" }
        let healthURL = httpURL.appendingPathComponent("api/chasetactical")
        var req = URLRequest(url: healthURL, timeoutInterval: 5)
        req.httpMethod = "GET"
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run { self.connectionDiag = "HTTP OK (\(status)) — opening WS…" }
            } catch {
                await MainActor.run {
                    self.connectionDiag = "HTTP failed: \(error.localizedDescription)"
                }
                self.scheduleReconnect()
                return  // don't attempt WS if HTTP is unreachable
            }

            // ── WebSocket connect ──────────────────────────────────────────
            comps.scheme = comps.scheme == "https" ? "wss" : "ws"
            comps.path   = "/ws"
            guard let wsURL = comps.url else { return }

            let task = URLSession.shared.webSocketTask(with: wsURL)
            await MainActor.run { self.wsTask = task }
            task.resume()
            self.reconnectDelay = 2
            task.sendPing { error in
                Task { @MainActor in
                    if let error {
                        HubClient.shared.connectionDiag = "WS ping failed: \(error.localizedDescription)"
                        HubClient.shared.isConnected = false
                    } else {
                        HubClient.shared.connectionDiag = "Connected ✓"
                        HubClient.shared.isConnected = true
                    }
                }
                if error != nil {
                    Task { @MainActor in
                        HubClient.shared.scheduleReconnect()
                    }
                }
            }
            self.receive(task: task)
        }
    }

    /// Disconnects and cancels any pending reconnect.
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func receive(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                DispatchQueue.main.async { self.isConnected = true }
                self.handleMessage(msg)
                self.receive(task: task)
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                    // Only overwrite diag if we haven't already shown a ping failure
                    if !self.connectionDiag.hasPrefix("Ping failed") {
                        self.connectionDiag = "Disconnected: \(error.localizedDescription)"
                    }
                }
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ msg: URLSessionWebSocketTask.Message) {
        // Future: parse pushed data updates here
        _ = msg
    }

    private func scheduleReconnect() {
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, maxDelay)
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.connect() }
        }
    }

    // MARK: - PDF API

    /// Fetch name + last-modified for each PDF (server must support /api/pdfs/meta).
    func fetchPdfMeta() async throws -> [PdfMeta] {
        let url = try endpoint("/api/pdfs/meta")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([PdfMeta].self, from: data)
    }

    /// Fetches the list of PDF filenames available on the hub.
    func fetchPdfList() async throws -> [String] {
        let url = try endpoint("/api/pdfs")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String].self, from: data)
    }

    /// Downloads the raw bytes of a PDF by filename.
    func fetchPdf(filename: String) async throws -> Data {
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw HubError.invalidFilename }
        let url = try endpoint("/api/pdfs/\(encoded)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200
        else { throw HubError.serverError }
        return data
    }

    func fetchPdfContext() async throws -> PdfContext {
        let url = try endpoint("/api/pdfs/context")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(PdfContext.self, from: data)
    }

    func fetchPdfOverrides(filename: String) async throws -> PdfOverridesPayload {
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw HubError.invalidFilename }

        let url = try endpoint("/api/pdf-overrides/\(encoded)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { throw HubError.serverError }
        guard !data.isEmpty else { return .empty }

        return (try? JSONDecoder().decode(PdfOverridesPayload.self, from: data)) ?? .empty
    }

    func fetchPdfWords(filename: String) async throws -> HubWordDocument {
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw HubError.invalidFilename }

        let url = try endpoint("/api/pdf-words/\(encoded)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200
        else { throw HubError.serverError }
        return try JSONDecoder().decode(HubWordDocument.self, from: data)
    }

    func fetchChaseTactical() async throws -> [ChaseCatalogItem] {
        let url = try endpoint("/api/chasetactical")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ChaseCatalogItem].self, from: data)
    }

    func fetchToughHooks() async throws -> [ToughHookCatalogItem] {
        let url = try endpoint("/api/toughhooks")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ToughHookCatalogItem].self, from: data)
    }

    func fetchCatalogLinks() async throws -> [CatalogLinkRecord] {
        let url = try endpoint("/api/links")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([CatalogLinkRecord].self, from: data)
    }

    func upsertCatalogLink(_ payload: CatalogLinkPayload) async throws -> CatalogLinkRecord {
        let url = try endpoint("/api/links")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { throw HubError.serverError }
        return try JSONDecoder().decode(CatalogLinkRecord.self, from: data)
    }

    func deleteCatalogLink(id: String) async throws {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw HubError.invalidFilename }
        let url = try endpoint("/api/links/\(encoded)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { throw HubError.serverError }
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) throws -> URL {
        let base = activeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let url = URL(string: base + path)
        else { throw HubError.noActiveUrl }
        return url
    }

    // MARK: - IP management helpers

    static func savedUrls() -> [String] {
        UserDefaults.standard.stringArray(forKey: savedUrlsKey) ?? []
    }

    static func addUrl(_ url: String) {
        var list = savedUrls()
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !list.contains(trimmed) else { return }
        list.append(trimmed)
        UserDefaults.standard.set(list, forKey: savedUrlsKey)
    }

    static func removeUrl(_ url: String) {
        let list = savedUrls().filter { $0 != url }
        UserDefaults.standard.set(list, forKey: savedUrlsKey)
        // If deleted URL was active, clear active
        if UserDefaults.standard.string(forKey: activeUrlKey) == url {
            UserDefaults.standard.removeObject(forKey: activeUrlKey)
        }
    }

    static func setActiveUrl(_ url: String) {
        UserDefaults.standard.set(url, forKey: activeUrlKey)
        // Auto-connect whenever the active URL changes
        Task { await MainActor.run { HubClient.shared.connect() } }
    }
}

// MARK: - Errors

enum HubError: LocalizedError {
    case noActiveUrl
    case invalidFilename
    case serverError

    var errorDescription: String? {
        switch self {
        case .noActiveUrl:      return "No active Hub URL set. Go to Settings (page 8) to add one."
        case .invalidFilename:  return "Invalid filename."
        case .serverError:      return "Server returned an error."
        }
    }
}
