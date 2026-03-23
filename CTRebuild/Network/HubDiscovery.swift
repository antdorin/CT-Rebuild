import Foundation
import Darwin

// MARK: - Hub Discovery
// Uses POSIX UDP sockets — NWFramework doesn't support broadcast to 255.255.255.255 on iOS.
// iPhone sends "CT-DISCOVER" broadcast to port 5052.
// Desktop replies "CT-HUB:{port}" back on port 5051.

enum HubDiscovery {
    private static let discoverPort: UInt16 = 5052
    private static let replyPort: UInt16    = 5051
    private static let timeoutSec: Int      = 5

    static func discover() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: discoverSync())
            }
        }
    }

    private static func discoverSync() -> String? {
        // ── Send socket (broadcast) ───────────────────────────────────────────
        let sendSock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sendSock >= 0 else { return nil }
        defer { close(sendSock) }

        var broadcastOn: Int32 = 1
        setsockopt(sendSock, SOL_SOCKET, SO_BROADCAST,
                   &broadcastOn, socklen_t(MemoryLayout<Int32>.size))

        // ── Receive socket (bound to 5051) ────────────────────────────────────
        let recvSock = socket(AF_INET, SOCK_DGRAM, 0)
        guard recvSock >= 0 else { return nil }
        defer { close(recvSock) }

        var reuseAddr: Int32 = 1
        setsockopt(recvSock, SOL_SOCKET, SO_REUSEADDR,
                   &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: timeoutSec, tv_usec: 0)
        setsockopt(recvSock, SOL_SOCKET, SO_RCVTIMEO,
                   &tv, socklen_t(MemoryLayout<timeval>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port   = replyPort.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(recvSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        // ── Send broadcast ────────────────────────────────────────────────────
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port   = discoverPort.bigEndian
        dest.sin_addr.s_addr = UInt32(0xFFFFFFFF).bigEndian  // 255.255.255.255
        let payload = Array("CT-DISCOVER".utf8)
        withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { destPtr in
                sendto(sendSock, payload, payload.count, 0,
                       destPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // ── Wait for reply ────────────────────────────────────────────────────
        var buf = [UInt8](repeating: 0, count: 256)
        var sender = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &sender) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(recvSock, &buf, buf.count, 0, $0, &senderLen)
            }
        }
        guard n > 0 else { return nil }

        let reply = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
        guard reply.hasPrefix("CT-HUB:"),
              let port = Int(reply.dropFirst("CT-HUB:".count))
        else { return nil }

        // Extract sender IP
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var inAddr = sender.sin_addr
        inet_ntop(AF_INET, &inAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: ipBuf)

        return "http://\(ip):\(port)"
    }
}

