package com.chasetactical.ctrebuild.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * UDP-based Hub auto-discovery — mirrors iOS HubDiscovery.swift.
 *
 * Protocol:
 *   1. Send "CT-DISCOVER" probe to 255.255.255.255:5052
 *   2. Hub replies "CT-HUB:5050" to the caller's source IP on port 5051
 *   3. Parse the reply to build the full http:// URL
 */
object HubDiscovery {

    private const val SEND_PORT   = 5052
    private const val LISTEN_PORT = 5051
    private const val PROBE       = "CT-DISCOVER"
    private const val REPLY_PREFIX = "CT-HUB:"
    private const val TIMEOUT_MS  = 5_000

    /**
     * Sends a discovery probe and waits for a Hub reply.
     * Returns a full "http://ip:port" string, or null if nothing responds within the timeout.
     * Must be called from a coroutine (suspends on I/O dispatcher).
     */
    suspend fun discover(): String? = withContext(Dispatchers.IO) {
        var listenSocket: DatagramSocket? = null
        var sendSocket: DatagramSocket? = null
        try {
            // Bind listen socket first so we don't miss the reply
            listenSocket = DatagramSocket(LISTEN_PORT).apply {
                soTimeout = TIMEOUT_MS
            }

            // Send broadcast probe
            sendSocket = DatagramSocket().apply { broadcast = true }
            val probeBytes = PROBE.toByteArray(Charsets.UTF_8)
            sendSocket.send(
                DatagramPacket(
                    probeBytes, probeBytes.size,
                    InetAddress.getByName("255.255.255.255"), SEND_PORT
                )
            )
            sendSocket.close()
            sendSocket = null

            // Wait for Hub reply
            val buf = ByteArray(64)
            val reply = DatagramPacket(buf, buf.size)
            listenSocket.receive(reply)

            val message = String(reply.data, 0, reply.length, Charsets.UTF_8).trim()
            if (message.startsWith(REPLY_PREFIX)) {
                val port = message.removePrefix(REPLY_PREFIX).trim()
                val ip   = reply.address.hostAddress
                "http://$ip:$port"
            } else null
        } catch (_: Exception) {
            null
        } finally {
            listenSocket?.close()
            sendSocket?.close()
        }
    }
}
