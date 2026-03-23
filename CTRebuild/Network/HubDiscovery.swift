import Foundation
import Darwin

// MARK: - Hub Discovery
// Two-pronged approach for maximum reliability:
//
//  1. Sends a "CT-DISCOVER" UDP probe to 255.255.255.255:5052.
//     • Critically, this outbound packet triggers the iOS local-network
//       permission dialog so the OS doesn't silently block incoming UDP.
//     • Desktop receives the probe and replies immediately with "CT-HUB:{port}".
//
//  2. Simultaneously binds :5051 and waits for the desktop's periodic broadcast
//     beacon (subnet-directed, e.g. 192.168.1.255:5051 — NOT 255.255.255.255,
//     which is filtered by most Wi-Fi APs).
//
//  Whichever arrives first (direct reply or broadcast beacon) is used.

enum HubDiscovery {
    private static let probeTargetPort: UInt16  = 5052 // desktop listens for CT-DISCOVER
    private static let listenPort: UInt16        = 5051 // phone listens for beacon / reply
    private static let timeoutSec: Int           = 10

    static func discover() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: discoverSync())
            }
        }
    }

    private static func discoverSync() -> String? {
        // ── Listen socket — bound to :5051, receives both the direct reply
        //    (desktop sends back to our IP:5051) and the broadcast beacon ──────
        let recvSock = socket(AF_INET, SOCK_DGRAM, 0)
        guard recvSock >= 0 else { return nil }
        defer { close(recvSock) }

        var reuseAddr: Int32 = 1
        setsockopt(recvSock, SOL_SOCKET, SO_REUSEADDR,
                   &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: timeoutSec, tv_usec: 0)
        setsockopt(recvSock, SOL_SOCKET, SO_RCVTIMEO,
                   &tv, socklen_t(MemoryLayout<timeval>.size))

        // Allow receiving broadcast packets
        var broadcastOn: Int32 = 1
        setsockopt(recvSock, SOL_SOCKET, SO_BROADCAST,
                   &broadcastOn, socklen_t(MemoryLayout<Int32>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_family      = sa_family_t(AF_INET)
        bindAddr.sin_port        = listenPort.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(recvSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        // ── Probe send — triggers iOS local-network permission dialog ─────────
        // Desktop also replies immediately to this probe (via DiscoveryLoopAsync)
        // so we don't have to wait for the next 3-second broadcast beacon.
        let sendSock = socket(AF_INET, SOCK_DGRAM, 0)
        if sendSock >= 0 {
            var broadOn: Int32 = 1
            setsockopt(sendSock, SOL_SOCKET, SO_BROADCAST,
                       &broadOn, socklen_t(MemoryLayout<Int32>.size))
            var dest = sockaddr_in()
            dest.sin_family      = sa_family_t(AF_INET)
            dest.sin_port        = probeTargetPort.bigEndian
            dest.sin_addr.s_addr = UInt32(0xFFFFFFFF).bigEndian // 255.255.255.255
            let probe = Array("CT-DISCOVER".utf8)
            withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                    sendto(sendSock, probe, probe.count, 0,
                           ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(sendSock)
        }

        // ── Wait for reply or beacon ──────────────────────────────────────────
        var buf = [UInt8](repeating: 0, count: 256)
        var sender    = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &sender) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(recvSock, &buf, buf.count, 0, $0, &senderLen)
            }
        }
        guard n > 0 else { return nil }

        let msg = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
        guard msg.hasPrefix("CT-HUB:"),
              let port = Int(msg.dropFirst("CT-HUB:".count))
        else { return nil }

        var ipBuf  = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var inAddr = sender.sin_addr
        inet_ntop(AF_INET, &inAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: ipBuf)

        return "http://\(ip):\(port)"
    }
}


