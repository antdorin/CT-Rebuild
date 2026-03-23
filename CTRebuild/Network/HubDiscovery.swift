import Foundation
import Darwin

// MARK: - Hub Discovery
// Uses POSIX UDP sockets — NWFramework doesn't support broadcast on iOS.
// The desktop CT-Hub broadcasts "CT-HUB:{port}" to 255.255.255.255:5051 every 3 s.
// The phone just binds to port 5051 and waits — no outbound packet needed,
// so no inbound Windows firewall rule is required on the desktop side.

enum HubDiscovery {
    private static let listenPort: UInt16 = 5051
    private static let timeoutSec: Int    = 10   // wait up to 10 s per attempt

    static func discover() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: discoverSync())
            }
        }
    }

    private static func discoverSync() -> String? {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        // Allow quick re-bind if the port is in TIME_WAIT from a prior run
        var reuseAddr: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR,
                   &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // Timeout so the caller can retry without hanging forever
        var tv = timeval(tv_sec: timeoutSec, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO,
                   &tv, socklen_t(MemoryLayout<timeval>.size))

        // Bind to 0.0.0.0:5051 to receive broadcasts
        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port   = listenPort.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        // Wait for the desktop beacon "CT-HUB:{port}"
        var buf = [UInt8](repeating: 0, count: 256)
        var sender = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &sender) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(sock, &buf, buf.count, 0, $0, &senderLen)
            }
        }
        guard n > 0 else { return nil }

        let reply = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
        guard reply.hasPrefix("CT-HUB:"),
              let port = Int(reply.dropFirst("CT-HUB:".count))
        else { return nil }

        // Extract sender IP from the sockaddr
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var inAddr = sender.sin_addr
        inet_ntop(AF_INET, &inAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: ipBuf)

        return "http://\(ip):\(port)"
    }
}

