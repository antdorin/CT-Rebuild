import Foundation
import Network

// MARK: - Hub Discovery
// iPhone sends one UDP broadcast to port 5052.
// Desktop receives it and replies "CT-HUB:{port}" directly back on port 5051.
// Phone parses the reply, builds the full URL, done.

enum HubDiscovery {
    private static let discoverPort: UInt16 = 5052
    private static let replyPort: UInt16    = 5051
    private static let timeout: TimeInterval = 5

    /// Sends a single discovery probe and waits up to 5 s for a reply.
    /// Returns a full URL string e.g. "http://192.168.1.42:5050", or nil on timeout.
    static func discover() async -> String? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let q = DispatchQueue(label: "hub.discovery")

            let resume: (String?) -> Void = { result in
                q.sync {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: result)
                }
            }

            // ── Listen for reply on 5051 ──────────────────────────────────
            guard let listener = try? NWListener(
                using: .udp,
                on: NWEndpoint.Port(rawValue: replyPort)!)
            else { resume(nil); return }

            listener.newConnectionHandler = { conn in
                conn.start(queue: q)
                conn.receiveMessage { data, _, _, _ in
                    guard let data,
                          let msg = String(data: data, encoding: .utf8),
                          msg.hasPrefix("CT-HUB:"),
                          let port = Int(msg.dropFirst("CT-HUB:".count))
                    else { return }

                    // Extract sender IP from the connection's remote endpoint
                    if case .hostPort(let host, _) = conn.endpoint {
                        let ip = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                        listener.cancel()
                        resume("http://\(ip):\(port)")
                    }
                }
            }
            listener.start(queue: q)

            // ── Send broadcast to 5052 ────────────────────────────────────
            let probe = NWConnection(
                host: "255.255.255.255",
                port: NWEndpoint.Port(rawValue: discoverPort)!,
                using: .udp)
            probe.start(queue: q)
            let payload = "CT-DISCOVER".data(using: .utf8)!
            probe.send(content: payload, completion: .contentProcessed { _ in probe.cancel() })

            // ── Timeout ───────────────────────────────────────────────────
            q.asyncAfter(deadline: .now() + timeout) {
                listener.cancel()
                resume(nil)
            }
        }
    }
}
