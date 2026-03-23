import Foundation

// MARK: - Hub Client

/// URLSession-based singleton for communicating with CT-Hub.
/// Active base URL is read from UserDefaults key "hubActiveUrl".
final class HubClient {
    static let shared = HubClient()
    private init() {}

    // Key used to store the active IP in UserDefaults
    static let activeUrlKey = "hubActiveUrl"
    static let savedUrlsKey = "hubSavedUrls"

    var activeBaseURL: String {
        UserDefaults.standard.string(forKey: HubClient.activeUrlKey) ?? ""
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
        var list = savedUrls().filter { $0 != url }
        UserDefaults.standard.set(list, forKey: savedUrlsKey)
        // If deleted URL was active, clear active
        if UserDefaults.standard.string(forKey: activeUrlKey) == url {
            UserDefaults.standard.removeObject(forKey: activeUrlKey)
        }
    }

    static func setActiveUrl(_ url: String) {
        UserDefaults.standard.set(url, forKey: activeUrlKey)
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
