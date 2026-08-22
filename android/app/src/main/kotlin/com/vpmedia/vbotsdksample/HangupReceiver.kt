package com.vpmedia.vbotsdksample

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.Log

/**
 * BroadcastReceiver xử lý action "Tắt máy" từ ongoing call notification.
 */
class HangupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("VBotPhone", "HangupReceiver -> ending call from notification")
        if (MainActivity.clientExists()) {
            MainActivity.client.endCall()
        }
    }
}
