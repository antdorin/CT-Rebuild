package com.chasetactical.ctrebuild.ui.dashboard

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.flow.MutableStateFlow

@Composable
fun OutlookWidget(modifier: Modifier = Modifier) {
    val stateFlow = remember { MutableStateFlow<OutlookState>(OutlookState.Loading) }
    val state     by stateFlow.collectAsState()

    // Timeout: if still loading after 20s, transition to NeedsSignIn
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(20_000)
        if (stateFlow.value is OutlookState.Loading) {
            stateFlow.value = OutlookState.NeedsSignIn
        }
    }

    val isSignIn = state is OutlookState.NeedsSignIn

    // Outer box clips the rounded corners and sizes the widget
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Color.Transparent)
    ) {
        // WebView is ALWAYS present so sessions/cookies are preserved.
        // When NeedsSignIn it fills the widget so the user can sign in directly here.
        OutlookScrapeView(stateFlow = stateFlow, fullSize = isSignIn)

        // Content overlay — shown for Loading and Loaded states only
        if (!isSignIn) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Transparent)
                    .padding(14.dp),
                contentAlignment = Alignment.Center
            ) {
                when (val s = state) {
                    is OutlookState.Loading -> Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        CircularProgressIndicator(
                            color = Color(0xFFFF9500),
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp
                        )
                        Text("Loading inbox…", color = Color(0xFF666666), fontSize = 11.sp)
                    }

                    is OutlookState.Loaded -> Column(modifier = Modifier.fillMaxSize()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(bottom = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "✉️  Inbox",
                                color = Color(0xFFFF9500),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Black
                            )
                            val unreadCount = s.emails.count { it.isUnread }
                            if (unreadCount > 0) {
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(Color(0xFFFF9500))
                                        .padding(horizontal = 7.dp, vertical = 2.dp)
                                ) {
                                    Text(
                                        "$unreadCount unread",
                                        color = Color.Black,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                            }
                        }
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.spacedBy(0.dp)
                        ) {
                            items(
                                s.emails,
                                key = { "${it.sender}${it.subject}${it.receivedTime}" }
                            ) { mail ->
                                MailRow(mail) {
                                    stateFlow.value = OutlookState.Loading
                                }
                                HorizontalDivider(color = Color(0xFF1A1A1A), thickness = 0.5.dp)
                            }
                        }
                    }

                    else -> Unit // NeedsSignIn handled by fullSize branch above
                }
            }
        } else {
            // Sign-in hint badge at the bottom of the full-size Outlook WebView
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(Color(0xDD0A0D14))
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                Text(
                    "Sign in to Outlook above to see your inbox",
                    color = Color(0xFFFF9500),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

@Composable
private fun MailRow(mail: MailItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 9.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Unread indicator
        Box(
            modifier = Modifier
                .padding(top = 5.dp)
                .size(6.dp)
                .clip(CircleShape)
                .background(if (mail.isUnread) Color(0xFFFF9500) else Color.Transparent)
        )

        // Sender avatar initial
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(Color(0xFF1E2A3A)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                mail.sender.firstOrNull()?.uppercaseChar()?.toString() ?: "?",
                color = Color(0xFFFF9500),
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    mail.sender,
                    color = if (mail.isUnread) Color.White else Color(0xFFAAAAAA),
                    fontSize = 12.sp,
                    fontWeight = if (mail.isUnread) FontWeight.Bold else FontWeight.Normal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    mail.receivedTime,
                    color = Color(0xFF555555),
                    fontSize = 9.sp,
                    modifier = Modifier.padding(start = 4.dp)
                )
            }
            Text(
                mail.subject,
                color = if (mail.isUnread) Color(0xFFDDDDDD) else Color(0xFF888888),
                fontSize = 11.sp,
                fontWeight = if (mail.isUnread) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (mail.preview.isNotEmpty()) {
                Text(
                    mail.preview,
                    color = Color(0xFF555555),
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
