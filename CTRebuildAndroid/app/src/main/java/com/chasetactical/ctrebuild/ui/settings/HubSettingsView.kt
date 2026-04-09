package com.chasetactical.ctrebuild.ui.settings

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chasetactical.ctrebuild.network.HubClient
import com.chasetactical.ctrebuild.network.HubDiscovery
import kotlinx.coroutines.launch

private const val PREFS_NAME = "ct_rebuild"
private const val KEY_HUB_URL = "hub_url"

/**
 * Settings screen for configuring the Hub URL.
 * Uses UDP broadcast discovery or manual URL entry.
 * Persists the URL in SharedPreferences under "ct_rebuild"/"hub_url".
 */
@Composable
fun HubSettingsView(onBack: (() -> Unit)? = null, onUrlSaved: () -> Unit = {}) {
    val context      = LocalContext.current
    val scope        = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current

    val prefs = remember { context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

    var urlInput    by remember { mutableStateOf(prefs.getString(KEY_HUB_URL, "") ?: "") }
    var status      by remember { mutableStateOf("") }
    var discovering by remember { mutableStateOf(false) }
    var connected   by remember { mutableStateOf(false) }

    // Verify saved URL on first composition
    LaunchedEffect(Unit) {
        val saved = prefs.getString(KEY_HUB_URL, "") ?: ""
        if (saved.isNotEmpty()) {
            HubClient.shared.activeUrl = saved
            connected = HubClient.shared.testConnection()
            status = if (connected) "Connected to $saved" else "Cannot reach $saved"
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F0F))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) {
                IconButton(onClick = onBack, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = Color(0xFFFF9500)
                    )
                }
                Spacer(Modifier.width(4.dp))
            }
            Text(
                text = "Hub Connection",
                color = Color(0xFFFF9500),
                fontSize = 20.sp,
                fontWeight = FontWeight.Black
            )
        }

        // Connection status dot + message
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .background(
                        color = if (connected) Color(0xFF4CAF50) else Color(0xFFFF5252),
                        shape = MaterialTheme.shapes.small
                    )
            )
            Text(
                text = if (connected) "Connected"
                       else status.ifEmpty { "Not connected" },
                color = Color(0xFFB7B7B7),
                fontSize = 13.sp
            )
        }

        // Auto-discover button
        Button(
            onClick = {
                scope.launch {
                    discovering = true
                    status      = "Searching…"
                    connected   = false
                    val found = HubDiscovery.discover()
                    if (found != null) {
                        urlInput = found
                        HubClient.shared.activeUrl = found
                        prefs.edit().putString(KEY_HUB_URL, found).apply()
                        onUrlSaved()
                        connected = HubClient.shared.testConnection()
                        status    = if (connected) "Found: $found" else "Found but unreachable: $found"
                    } else {
                        status = "No Hub found on network"
                    }
                    discovering = false
                }
            },
            enabled = !discovering,
            colors  = ButtonDefaults.buttonColors(containerColor = Color(0xFF1E3A5F)),
            modifier = Modifier.fillMaxWidth()
        ) {
            if (discovering) {
                CircularProgressIndicator(
                    modifier  = Modifier.size(16.dp),
                    color     = Color(0xFFFF9500),
                    strokeWidth = 2.dp
                )
                Spacer(Modifier.width(8.dp))
            }
            Text(
                text  = if (discovering) "Searching…" else "Find Hub on Network",
                color = Color(0xFFFF9500)
            )
        }

        HorizontalDivider(color = Color(0xFF2A2A2A))

        Text("Manual URL", color = Color(0xFFB7B7B7), fontSize = 12.sp)

        OutlinedTextField(
            value       = urlInput,
            onValueChange = { urlInput = it },
            placeholder = { Text("http://192.168.1.x:5050", color = Color(0xFF666666)) },
            singleLine  = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Uri,
                imeAction    = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor     = Color.White,
                unfocusedTextColor   = Color.White,
                focusedBorderColor   = Color(0xFFFF9500),
                unfocusedBorderColor = Color(0xFF3A3A3A),
                cursorColor          = Color(0xFFFF9500)
            ),
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = {
                scope.launch {
                    focusManager.clearFocus()
                    val url = urlInput.trim().trimEnd('/')
                    HubClient.shared.activeUrl = url
                    prefs.edit().putString(KEY_HUB_URL, url).apply()
                    onUrlSaved()
                    status    = "Testing…"
                    connected = false
                    connected = HubClient.shared.testConnection()
                    status    = if (connected) "Connected to $url" else "Could not reach $url"
                }
            },
            colors   = ButtonDefaults.buttonColors(containerColor = Color(0xFF1E3A5F)),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Connect", color = Color(0xFFFF9500))
        }
    }
}
