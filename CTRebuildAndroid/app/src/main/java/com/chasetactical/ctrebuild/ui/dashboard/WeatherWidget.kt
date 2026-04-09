package com.chasetactical.ctrebuild.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chasetactical.ctrebuild.models.WeatherDay
import com.chasetactical.ctrebuild.models.WeatherStore

@Composable
fun WeatherWidget(modifier: Modifier = Modifier) {
    val state by WeatherStore.state.collectAsState()

    LaunchedEffect(Unit) {
        if (state.loading || state.city.isEmpty()) WeatherStore.refresh()
    }

    Box(
        modifier = modifier
            .background(Color.Transparent)
            .padding(14.dp),
        contentAlignment = Alignment.Center
    ) {
        when {
            state.loading -> CircularProgressIndicator(
                color = Color(0xFFFF9500),
                modifier = Modifier.size(28.dp),
                strokeWidth = 2.dp
            )
            state.error != null -> Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text("⚠", fontSize = 28.sp)
                Text(
                    "Weather unavailable",
                    color = Color(0xFF888888),
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center
                )
            }
            else -> Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                // City + main temp
                Column {
                    if (state.city.isNotEmpty()) {
                        Text(
                            state.city,
                            color = Color(0xFF888888),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(state.emoji, fontSize = 36.sp)
                        Column {
                            Text(
                                "${state.tempC}°",
                                color = Color.White,
                                fontSize = 40.sp,
                                fontWeight = FontWeight.Black,
                                lineHeight = 40.sp
                            )
                            Text(
                                state.desc,
                                color = Color(0xFFAAAAAA),
                                fontSize = 11.sp
                            )
                        }
                    }
                }

                // Feels like + humidity + wind
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    WeatherStat("Feels", "${state.feelsLike}°", Modifier.weight(1f))
                    WeatherStat("Humid", "${state.humidity}%", Modifier.weight(1f))
                    WeatherStat("Wind", "${state.windKph.toInt()} km/h", Modifier.weight(1f))
                }

                // 3-day forecast
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    state.forecast.forEach { day ->
                        ForecastDay(day, Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun WeatherStat(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0xFF1A2A3A))
            .padding(horizontal = 6.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(label, color = Color(0xFF666666), fontSize = 9.sp, fontFamily = FontFamily.Monospace)
        Text(value, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ForecastDay(day: WeatherDay, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0xFF1A1A2A))
            .padding(horizontal = 4.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(day.dayLabel, color = Color(0xFFFF9500), fontSize = 9.sp, fontWeight = FontWeight.Bold)
        Text(day.emoji, fontSize = 18.sp)
        Text("${day.high}°", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Text("${day.low}°", color = Color(0xFF666666), fontSize = 10.sp)
    }
}
