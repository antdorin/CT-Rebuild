package com.chasetactical.ctrebuild.models

import com.google.gson.JsonParser
import okhttp3.OkHttpClient
import okhttp3.Request
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate

data class WeatherDay(
    val dayLabel: String,   // "Mon", "Tue", etc.
    val high: Int,
    val low: Int,
    val desc: String,
    val emoji: String
)

data class WeatherState(
    val city: String       = "",
    val tempC: Int         = 0,
    val feelsLike: Int     = 0,
    val desc: String       = "",
    val emoji: String      = "🌡",
    val humidity: Int      = 0,
    val windKph: Double    = 0.0,
    val forecast: List<WeatherDay> = emptyList(),
    val loading: Boolean   = true,
    val error: String?     = null
)

object WeatherStore {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient()

    private val _state = MutableStateFlow(WeatherState())
    val state: StateFlow<WeatherState> = _state

    /** Call once (e.g. from Application.onCreate). Uses IP geolocation automatically. */
    fun refresh() {
        scope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            try {
                // 1. Geolocate by IP (ipapi.co — free, no key, returns lat/lon/city)
                val locReq  = Request.Builder()
                    .url("https://ipapi.co/json/")
                    .header("User-Agent", "CTRebuild/1.0")
                    .build()
                val locJson = client.newCall(locReq).execute().use { resp ->
                    JsonParser.parseString(resp.body.string()).asJsonObject
                }
                val lat     = locJson.get("latitude").asDouble
                val lon     = locJson.get("longitude").asDouble
                val city    = locJson.get("city")?.asString ?: ""
                val country = locJson.get("country_name")?.asString ?: ""

                // 2. Fetch weather from Open-Meteo (truly free, no API key)
                val wUrl = "https://api.open-meteo.com/v1/forecast?" +
                    "latitude=$lat&longitude=$lon" +
                    "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code" +
                    "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
                    "&timezone=auto&forecast_days=3"
                val wReq  = Request.Builder()
                    .url(wUrl)
                    .header("User-Agent", "CTRebuild/1.0")
                    .build()
                val wRoot = client.newCall(wReq).execute().use { resp ->
                    JsonParser.parseString(resp.body.string()).asJsonObject
                }

                val cur      = wRoot.getAsJsonObject("current")
                val tempC    = cur.get("temperature_2m").asDouble.toInt()
                val feelsC   = cur.get("apparent_temperature").asDouble.toInt()
                val humidity = cur.get("relative_humidity_2m").asInt
                val windKph  = cur.get("wind_speed_10m").asDouble
                val code     = cur.get("weather_code").asInt

                val daily  = wRoot.getAsJsonObject("daily")
                val times  = daily.getAsJsonArray("time")
                val codes  = daily.getAsJsonArray("weather_code")
                val maxTs  = daily.getAsJsonArray("temperature_2m_max")
                val minTs  = daily.getAsJsonArray("temperature_2m_min")

                val dayLabels = listOf(
                    "Today", "Tomorrow",
                    runCatching { LocalDate.parse(times[2].asString).dayOfWeek.name.take(3)
                        .lowercase().replaceFirstChar { it.uppercase() } }.getOrElse { "Day 3" }
                )
                val forecast = (0 until minOf(3, times.size())).map { i ->
                    val dc = codes[i].asInt
                    WeatherDay(
                        dayLabel = dayLabels.getOrElse(i) { "Day ${i + 1}" },
                        high     = maxTs[i].asDouble.toInt(),
                        low      = minTs[i].asDouble.toInt(),
                        desc     = wmoDescription(dc),
                        emoji    = wmoEmoji(dc)
                    )
                }

                _state.value = WeatherState(
                    city      = if (city.isNotEmpty()) "$city, $country" else country,
                    tempC     = tempC,
                    feelsLike = feelsC,
                    desc      = wmoDescription(code),
                    emoji     = wmoEmoji(code),
                    humidity  = humidity,
                    windKph   = windKph,
                    forecast  = forecast,
                    loading   = false,
                    error     = null
                )
            } catch (e: Exception) {
                _state.value = WeatherState(loading = false, error = e.message ?: "Failed to load weather")
            }
        }
    }

    private fun wmoDescription(code: Int): String = when (code) {
        0    -> "Clear sky"
        1    -> "Mainly clear"
        2    -> "Partly cloudy"
        3    -> "Overcast"
        45, 48 -> "Foggy"
        51, 53, 55 -> "Drizzle"
        56, 57 -> "Freezing drizzle"
        61, 63, 65 -> "Rain"
        66, 67 -> "Freezing rain"
        71, 73, 75 -> "Snow"
        77   -> "Snow grains"
        80, 81, 82 -> "Rain showers"
        85, 86 -> "Snow showers"
        95   -> "Thunderstorm"
        96, 99 -> "Heavy thunderstorm"
        else -> "Unknown"
    }

    private fun wmoEmoji(code: Int): String = when (code) {
        0    -> "☀️"
        1, 2 -> "⛅"
        3    -> "☁️"
        45, 48 -> "🌫"
        51, 53, 55, 56, 57 -> "🌦"
        61, 63, 65, 66, 67, 80, 81, 82 -> "🌧"
        71, 73, 75, 77, 85, 86 -> "❄️"
        95, 96, 99 -> "⛈"
        else -> "🌡"
    }
}
