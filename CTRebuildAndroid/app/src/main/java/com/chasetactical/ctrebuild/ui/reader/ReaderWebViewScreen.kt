package com.chasetactical.ctrebuild.ui.reader

import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView
import com.chasetactical.ctrebuild.network.HubClient

/**
 * Full-screen WebView that loads the Hub reader.html for the given filename.
 * JS and DOM storage are enabled so the reader's layout engine works correctly.
 */
@Composable
fun ReaderWebViewScreen(filename: String, onWebViewCreated: (WebView) -> Unit = {}) {
    val url = HubClient.shared.getReaderUrl(filename)

    AndroidView(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        factory = { context ->
            WebView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                settings.apply {
                    javaScriptEnabled    = true
                    domStorageEnabled    = true
                    allowFileAccess      = false
                    databaseEnabled      = true
                    useWideViewPort      = true
                    loadWithOverviewMode = true
                    setSupportZoom(false)
                    builtInZoomControls  = false
                    displayZoomControls  = false
                    mediaPlaybackRequiresUserGesture = false
                }
                webChromeClient = WebChromeClient()
                webViewClient   = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = false
                }
                loadUrl(url)
                onWebViewCreated(this)
            }
        },
        update = { webView ->
            if (webView.url != url) webView.loadUrl(url)
        }
    )
}
