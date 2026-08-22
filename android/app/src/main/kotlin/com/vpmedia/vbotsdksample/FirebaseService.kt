package com.vpmedia.vbotsdksample

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.vpmedia.sdkvbot.client.ClientListener
import com.vpmedia.sdkvbot.en.CallState
import io.flutter.Log

class FirebaseService : FirebaseMessagingService() {

    companion object {
        @Volatile
        private var incomingCallListener: ClientListener? = null
    }

    /**
     * Đăng ký listener để launch MainActivity khi user accept cuộc gọi từ notification SDK.
     */
    private fun registerIncomingCallListener() {
        if (incomingCallListener != null) {
            MainActivity.client.addListener(incomingCallListener!!)
            return
        }

        val appContext = applicationContext
        val listener = object : ClientListener() {
            override fun onCallState(state: CallState) {
                Log.d("VBotPhone", "FirebaseService.listener.onCallState: $state")
                when (state) {
                    CallState.Connecting, CallState.Confirmed -> {
                        MainActivity.currentCallState = if (state == CallState.Confirmed) "confirmed" else "connecting"

                        Handler(Looper.getMainLooper()).post {
                            try {
                                val intent = Intent(appContext, MainActivity::class.java).apply {
                                    addFlags(
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                                or Intent.FLAG_ACTIVITY_SINGLE_TOP
                                                or Intent.FLAG_ACTIVITY_CLEAR_TOP
                                    )
                                    putExtra("from_incoming_call", true)
                                }
                                appContext.startActivity(intent)
                                Log.d("VBotPhone", "FirebaseService -> launched MainActivity for: $state")
                            } catch (e: Exception) {
                                Log.d("VBotPhone", "FirebaseService -> launch failed: ${e.message}")
                            }
                        }
                    }
                    CallState.Disconnected, CallState.Null -> {
                        MainActivity.currentCallState = "none"
                        OngoingCallNotification.cancel(appContext)
                    }
                    else -> { /* Incoming: chỉ hiện notification SDK, không mở app */ }
                }
            }
        }
        incomingCallListener = listener
        MainActivity.client.addListener(listener)
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val map = HashMap(remoteMessage.data)

        if (map.containsKey("transId")) {
            val callerName = map["name"] ?: ""
            if (callerName.isNotEmpty()) {
                MainActivity.nameCall = callerName
                MainActivity.isIncoming = true
            }
            MainActivity.currentCallState = "incoming"
            Log.d("VBotPhone", "FirebaseService -> incoming call from: $callerName, data=$map")

            MainActivity.initClient(applicationContext)
            registerIncomingCallListener()

            // Dùng notification của SDK
            MainActivity.client.notificationCall(map)

            // Khi Flutter đang ở foreground, đẩy trạng thái incoming qua EventChannel
            // trước khi hủy notification SDK. Nếu Flutter chưa sẵn sàng thì giữ notification
            // native để người dùng vẫn có thể nhận cuộc gọi.
            if (MainActivity.isForeground && MainActivity.events != null) {
                Handler(Looper.getMainLooper()).post {
                    val callSink = CallSink(
                        MainActivity.nameCall,
                        "incoming",
                        true,
                        MainActivity.isMute,
                        MainActivity.onHold
                    )
                    MainActivity.events?.success(callSink.toMap())

                    try {
                        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancelAll()
                    } catch (_: Exception) {}
                }
            }
        }
    }
}
