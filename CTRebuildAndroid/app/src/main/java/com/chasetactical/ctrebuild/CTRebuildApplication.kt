package com.chasetactical.ctrebuild

import android.app.Application
import android.content.Context
import com.chasetactical.ctrebuild.models.ShippedStore
import com.chasetactical.ctrebuild.network.HubClient
import org.opencv.android.OpenCVLoader

class CTRebuildApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        OpenCVLoader.initLocal()
        ShippedStore.init(this)
        val prefs = getSharedPreferences("ct_rebuild", Context.MODE_PRIVATE)
        val savedUrl = prefs.getString("hub_url", "") ?: ""
        if (savedUrl.isNotEmpty()) {
            HubClient.shared.activeUrl = savedUrl
        }
    }
}
