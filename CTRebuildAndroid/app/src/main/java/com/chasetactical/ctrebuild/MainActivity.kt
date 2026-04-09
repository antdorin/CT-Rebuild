package com.chasetactical.ctrebuild

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.chasetactical.ctrebuild.network.HubClient
import com.chasetactical.ctrebuild.ui.DashboardScreen
import com.chasetactical.ctrebuild.ui.theme.CTRebuildTheme
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

class MainActivity : ComponentActivity() {

    private var hubWebSocket: WebSocket? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Restore saved Hub URL so network calls work immediately on first open
        val prefs = getSharedPreferences("ct_rebuild", Context.MODE_PRIVATE)
        val savedUrl = prefs.getString("hub_url", "") ?: ""
        if (savedUrl.isNotEmpty()) {
            HubClient.shared.activeUrl = savedUrl
            openHubWebSocket()
        }

        enableEdgeToEdge()

        // Request 60 Hz display mode (Samsung One UI / high-refresh panels)
        // Display.getSupportedModes() and preferredDisplayModeId were added in API 23.
        // windowManager.defaultDisplay is used here because window.display requires API 30.
        if (Build.VERSION.SDK_INT >= 23) {
            @Suppress("DEPRECATION")
            val modes = windowManager.defaultDisplay.supportedModes
            val target = modes.filter { it.refreshRate in 59f..61f }
                .maxByOrNull { it.physicalWidth * it.physicalHeight }
            if (target != null) {
                val attrs = window.attributes
                attrs.preferredDisplayModeId = target.modeId
                window.attributes = attrs
            }
        }

        val insetsController = WindowCompat.getInsetsController(window, window.decorView)
        insetsController.hide(WindowInsetsCompat.Type.navigationBars())
        insetsController.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        setContent {
            CTRebuildTheme {
                DashboardScreen(onHubUrlChanged = { openHubWebSocket() })
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        hubWebSocket?.close(1000, "app closing")
        hubWebSocket = null
    }

    fun openHubWebSocket() {
        hubWebSocket?.close(1000, "reconnecting")
        hubWebSocket = null

        if (HubClient.shared.activeUrl.isBlank()) return

        hubWebSocket = HubClient.shared.connectWebSocket(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d("HubWS", "Connected to Hub")
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w("HubWS", "WS failure: ${t.message}")
                hubWebSocket = null
            }
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
                hubWebSocket = null
            }
        })
    }
}
