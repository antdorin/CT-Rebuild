package com.chasetactical.ctrebuild.ui.dashboard

import android.annotation.SuppressLint
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.google.gson.JsonParser
import kotlinx.coroutines.flow.MutableStateFlow

data class TrafficIncident(
    val type: String,
    val description: String,
    val street: String,
    val severity: Int  // 1=minor, 2=moderate, 3=major, 4=critical
)

/** Hidden 1x1 WebView that loads Waze live-map, injects JS to extract incidents */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun TrafficScrapeView(incidents: MutableStateFlow<List<TrafficIncident>>) {
    val context = LocalContext.current
    val webView = remember {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(1, 1)
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                userAgentString = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/122.0 Mobile Safari/537.36"
            }
            webChromeClient = WebChromeClient()
        }
    }

    val bridge = remember {
        object : Any() {
            @JavascriptInterface
            fun onIncidents(json: String) {
                try {
                    val arr = JsonParser.parseString(json).asJsonArray
                    val list = arr.map { el ->
                        val o = el.asJsonObject
                        TrafficIncident(
                            type        = o.get("type")?.asString ?: "Incident",
                            description = o.get("description")?.asString ?: "",
                            street      = o.get("street")?.asString ?: "",
                            severity    = o.get("severity")?.asInt ?: 1
                        )
                    }
                    incidents.value = list
                } catch (_: Exception) {}
            }
        }
    }

    val injectJs = """
        (function() {
          try {
            // Try extracting from Waze SDK store if it exists
            var alerts = [];
            if (window.WazeMap) {
              var model = window.WazeMap.getModel && window.WazeMap.getModel();
              if (model) {
                var alertObjs = model.alerts && model.alerts.objects ? model.alerts.objects : {};
                Object.values(alertObjs).forEach(function(a) {
                  alerts.push({
                    type: a.type || 'Alert',
                    description: a.subtype || a.type || '',
                    street: a.street || '',
                    severity: a.reliability ? Math.min(4, Math.ceil(a.reliability / 3)) : 1
                  });
                });
              }
            }
            // Fallback: parse any visible alert DOM elements
            if (alerts.length === 0) {
              document.querySelectorAll('[data-testid*="alert"], .alert-item, .waze-incident').forEach(function(el) {
                alerts.push({
                  type: el.getAttribute('data-type') || el.className,
                  description: el.innerText.split('\n')[0] || '',
                  street: el.innerText.split('\n')[1] || '',
                  severity: 1
                });
              });
            }
            window.AndroidBridge.onIncidents(JSON.stringify(alerts.slice(0, 20)));
          } catch(e) {
            window.AndroidBridge.onIncidents('[]');
          }
        })();
    """.trimIndent()

    AndroidView(
        factory = {
            webView.apply {
                addJavascriptInterface(bridge, "AndroidBridge")
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = false
                    override fun onPageFinished(view: WebView, url: String) {
                        // Wait a moment for the JS app to boot, then extract
                        view.postDelayed({ view.evaluateJavascript(injectJs, null) }, 3000)
                    }
                }
                loadUrl("https://www.waze.com/live-map/")
            }
        }
    )

    DisposableEffect(Unit) {
        onDispose { webView.destroy() }
    }
}
