import Foundation
import Combine

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

        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.path   = "/ws"
        guard let wsURL = comps.url else { return }

        let task = URLSession.shared.webSocketTask(with: wsURL)
        wsTask = task
        DispatchQueue.main.async { self.connectionDiag = "Connecting to \(wsURL.host ?? "?")…" }
        task.resume()
        reconnectDelay = 2
        // Send a ping immediately so the server registers the connection,
        // and set isConnected as soon as the ping is acknowledged.
        task.sendPing { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.connectionDiag = "Ping failed: \(error.localizedDescription)"
                    self.isConnected = false
                } else {
                    self.connectionDiag = "Connected ✓"
                    self.isConnected = true
                }
            }
            if error != nil { self.scheduleReconnect() }
        }
        receive(task: task)
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
