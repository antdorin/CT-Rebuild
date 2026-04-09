package com.chasetactical.ctrebuild.ui.dashboard

import android.annotation.SuppressLint
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import com.google.gson.JsonParser
import kotlinx.coroutines.flow.MutableStateFlow

data class MailItem(
    val sender: String,
    val subject: String,
    val preview: String,
    val isUnread: Boolean,
    val receivedTime: String
)

/** Signed-in or not state for the Outlook widget */
sealed class OutlookState {
    object Loading : OutlookState()
    object NeedsSignIn : OutlookState()
    data class Loaded(val emails: List<MailItem>) : OutlookState()
}

/** Hidden WebView that loads Outlook Web App, injects JS to extract inbox rows */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun OutlookScrapeView(
    stateFlow: MutableStateFlow<OutlookState>,
    fullSize: Boolean = false
) {
    val context = LocalContext.current
    val webView = remember {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                userAgentString = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/122.0 Mobile Safari/537.36"
            }
            webChromeClient = WebChromeClient()
            // Enable cookie persistence so sign-in survives app restarts
            CookieManager.getInstance().also { cm ->
                cm.setAcceptCookie(true)
                cm.setAcceptThirdPartyCookies(this, true)
            }
        }
    }

    val bridge = remember {
        object : Any() {
            @JavascriptInterface
            fun onEmails(json: String) {
                try {
                    val arr = JsonParser.parseString(json).asJsonArray
                    if (arr.size() == 0) return
                    val list = arr.map { el ->
                        val o = el.asJsonObject
                        MailItem(
                            sender      = o.get("sender")?.asString ?: "",
                            subject     = o.get("subject")?.asString ?: "(no subject)",
                            preview     = o.get("preview")?.asString ?: "",
                            isUnread    = o.get("unread")?.asBoolean ?: false,
                            receivedTime = o.get("time")?.asString ?: ""
                        )
                    }
                    stateFlow.value = OutlookState.Loaded(list)
                } catch (_: Exception) {}
            }

            @JavascriptInterface
            fun onNeedsSignIn() {
                stateFlow.value = OutlookState.NeedsSignIn
            }
        }
    }

    val injectJs = """
        (function() {
          try {
            // Detect sign-in page
            var isLoginPage = document.querySelector('[data-test-id="sign-in"], input[type="email"], #i0116') !== null;
            if (isLoginPage) { window.OutlookBridge.onNeedsSignIn(); return; }

            var emails = [];
            // OWA modern: message list rows
            var rows = document.querySelectorAll('[role="option"][aria-label], .customScrollBar [role="option"]');
            if (rows.length === 0) {
              // Fallback: look for table rows in classic OWA
              rows = document.querySelectorAll('tr[role="row"][data-convid], tr[role="row"][data-messageid]');
            }
            rows.forEach(function(row) {
              var senderEl = row.querySelector('[data-testid="SenderField"], .oL7W7, .PA6uG, [role="heading"][aria-level="3"]');
              var subjectEl = row.querySelector('[data-testid="SubjectLine"], .hcptR, .nDpYK, [role="heading"][aria-level="2"]');
              var previewEl = row.querySelector('[data-testid="MessageBodyPreview"], .lvl5m, .PZSRn');
              var timeEl    = row.querySelector('[data-testid="Timestamp"], time, .xfRFo');
              var unread    = row.getAttribute('aria-checked') === 'false' ||
                              row.classList.contains('isUnread') ||
                              row.getAttribute('data-is-unread') === 'true';
              emails.push({
                sender:  senderEl  ? senderEl.innerText.trim()  : '?',
                subject: subjectEl ? subjectEl.innerText.trim() : '(no subject)',
                preview: previewEl ? previewEl.innerText.trim() : '',
                unread:  unread,
                time:    timeEl    ? timeEl.innerText.trim()    : ''
              });
            });
            window.OutlookBridge.onEmails(JSON.stringify(emails.slice(0, 25)));
          } catch(e) {
            window.OutlookBridge.onEmails('[]');
          }
        })();
    """.trimIndent()

    AndroidView(
        modifier = if (fullSize) Modifier.fillMaxSize() else Modifier.size(1.dp),
        factory = {
            webView.apply {
                addJavascriptInterface(bridge, "OutlookBridge")
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = false
                    override fun onPageFinished(view: WebView, url: String) {
                        // Give the React/Angular app time to render the inbox
                        view.postDelayed({ view.evaluateJavascript(injectJs, null) }, 3500)
                    }
                }
                loadUrl("https://outlook.office.com/mail/inbox")
            }
        },
        update = { view ->
            view.layoutParams = ViewGroup.LayoutParams(
                if (fullSize) ViewGroup.LayoutParams.MATCH_PARENT else 1,
                if (fullSize) ViewGroup.LayoutParams.MATCH_PARENT else 1
            )
        }
    )

    DisposableEffect(Unit) {
        onDispose { webView.destroy() }
    }
}
