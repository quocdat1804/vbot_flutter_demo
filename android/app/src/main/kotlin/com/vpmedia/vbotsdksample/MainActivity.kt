package com.vpmedia.vbotsdksample

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.content.Intent
import android.os.Looper
import android.net.Uri
import android.provider.Settings
import com.google.firebase.messaging.FirebaseMessaging
import com.vpmedia.sdkvbot.client.ClientListener
import com.vpmedia.sdkvbot.client.VBotClient
import com.vpmedia.sdkvbot.client.VBotCompletion
import com.vpmedia.sdkvbot.client.VBotConfig
import com.vpmedia.sdkvbot.client.VBotEnvironment
import com.vpmedia.sdkvbot.en.AccountRegistrationState
import com.vpmedia.sdkvbot.en.CallState
import com.vpmedia.sdkvbot.en.VBotCallEndParty
import com.vpmedia.sdkvbot.en.VBotEndCallReason
import com.vpmedia.vbotsdksample.ChannelName.CALL_STATE_CHANNEL
import com.vpmedia.vbotsdksample.ChannelName.VBOT_CHANNEL
import io.flutter.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

object ChannelName {
    const val VBOT_CHANNEL = "com.vpmedia.vbot-sdk/vbot_phone"
    const val CALL_STATE_CHANNEL = "com.vpmedia.vbot-sdk/call"
}

enum class Methods(val value: String) {
    ISUSERCONNECTED("isUserConnected"),
    USERDISPLAYNAME("userDisplayName"),
    CONNECT("connect"),
    DISCONNECT("disconnect"),
    STARTCALL("startCall"),
    GETHOTLINE("getHotlines"),
    ANSWER("answer"),
    HANGUP("hangup"),
    MUTE("mute"),
    SPEAKER("speaker"),
    SENDDTMF("sendDTMF"),
    HOLD("hold"),
}

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var tokenFirebase: String = ""
    private var resultWrapper: ResultWrapper? = null

    companion object {
        @SuppressLint("StaticFieldLeak")
        lateinit var client: VBotClient

        var events: EventChannel.EventSink? = null
        var nameCall = ""
        var currentCallState = "none"
        var isIncoming = false
        var isMute = false
        var isSpeaker = false
        var onHold = false

        var isForeground = false
        var isWaitingToAnswer = false

        fun clientExists(): Boolean {
            return ::client.isInitialized
        }

        fun initClient(context: Context) {
            if (clientExists()) return
            client = VBotClient(context)
            client.setup(VBotConfig(VBotEnvironment.PRODUCTION))
        }
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
    }

    override fun onPause() {
        super.onPause()
        isForeground = false
    }

    private var listener = object : ClientListener() {
        override fun onUserConnected(displayName: String) {
            Log.d("VBotPhone", "onUserConnected: $displayName")
        }

        override fun onAccountRegistrationState(status: AccountRegistrationState, reason: String) {
            Log.d("VBotPhone", "onAccountRegistrationState: status=$status, reason=$reason")
        }

        override fun onCallState(state: CallState) {
            runOnUiThread {
                Log.d("VBotPhone", "onCallState: $state")
                currentCallState = when (state) {
                    CallState.Null -> {
                        isIncoming = false
                        "none"
                    }
                    CallState.Calling, CallState.Early -> {
                        isIncoming = false
                        "calling"
                    }
                    CallState.Incoming -> {
                        isIncoming = true
                        // Ưu tiên tên từ push data (đã set ở FirebaseService),
                        // fallback sang SDK callName nếu chưa có
                        if (nameCall.isEmpty()) {
                            nameCall = client.callName() ?: ""
                        }
                        // Nếu app đang ở Foreground -> xóa notification banner
                        if (isForeground) {
                            try {
                                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                                notificationManager.cancelAll()
                            } catch (_: Exception) {}
                        }
                        "incoming"
                    }
                    CallState.Connecting -> "connecting"
                    CallState.Confirmed -> {
                        // Hiện ongoing notification khi cuộc gọi active
                        OngoingCallNotification.show(
                            applicationContext,
                            nameCall.ifEmpty { "Cuộc gọi" }
                        )
                        "confirmed"
                    }
                    else -> {
                        isMute = false
                        isSpeaker = false
                        // Hủy ongoing notification khi cuộc gọi kết thúc
                        OngoingCallNotification.cancel(applicationContext)
                        "disconnected"
                    }
                }

                val callSink = CallSink(
                    nameCall,
                    currentCallState,
                    isIncoming,
                    isMute,
                    onHold
                )
                events?.success(callSink.toMap())

                if (state == CallState.Disconnected || state == CallState.Null) {
                    isIncoming = false
                    nameCall = ""
                    currentCallState = "none"
                }
            }
        }

        override fun onCallEnded(reason: VBotEndCallReason, endedBy: VBotCallEndParty) {
            Log.d("VBotPhone", "onCallEnded: reason=${reason.name}, endedBy=${endedBy.name}")
        }

        override fun onExternalCallId(externalCallId: String) {
            Log.d("VBotPhone", "onExternalCallId: $externalCallId")
        }

        override fun onCallMuteStateChanged(muted: Boolean) {
            Log.d("VBotPhone", "onCallMuteStateChanged: muted=$muted (ignored, we manage mute state locally)")
        }

        override fun onNetworkUnreachable() {
            Log.d("VBotPhone", "onNetworkUnreachable")
        }

        override fun onErrorCode(erCode: Int, message: String) {
            Log.d("VBotPhone", "onErrorCode: $erCode -- $message")
            runOnUiThread {
                resultWrapper?.error(erCode.toString(), message, null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        initClient(context)
        client.addListener(listener)
        getTokenFirebase()

        GeneratedPluginRegistrant.registerWith(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VBOT_CHANNEL)
            .setMethodCallHandler(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_STATE_CHANNEL)
            .setStreamHandler(this)

        requestCallPermissions()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        // App được mở từ background khi có cuộc gọi đến
        if (intent.getBooleanExtra("from_incoming_call", false)) {
            emitCurrentCallState()
        }
    }

    /**
     * Emit trạng thái cuộc gọi hiện tại cho Flutter.
     * Cần thiết khi app được mở từ background — Flutter engine có thể
     * đã miss event ban đầu.
     */
    private fun emitCurrentCallState() {
        if (!clientExists() || !client.hasActiveCall()) return

        // Chỉ fallback sang client.callName() nếu chưa có tên từ push data
        if (nameCall.isEmpty()) {
            nameCall = client.callName() ?: ""
        }
        isMute = client.isCallMute()
        isIncoming = true

        val state = if (currentCallState != "none") currentCallState else {
            val duration = client.getDuration()
            if (duration != null && duration > 0) "confirmed" else "incoming"
        }

        val callSink = CallSink(nameCall, state, isIncoming, isMute, onHold)
        events?.success(callSink.toMap())
    }

    private fun requestCallPermissions() {
        val needed = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            needed.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val ungranted = needed.filter {
            context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (ungranted.isNotEmpty()) {
            requestPermissions(ungranted.toTypedArray(), 1)
        }

        // Xin quyền "Hiển thị trên các ứng dụng khác" (SYSTEM_ALERT_WINDOW / Display over other apps)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(context)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
            }
        }

        // Xin quyền Full Screen Intent trên Android 14+ nếu chưa được cấp (được rút ra từ kinh nghiệm vbot_android fixes)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.canUseFullScreenIntent()) {
                try {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                } catch (e: Exception) {
                    Log.e("VBotPhone", "Error opening MANAGE_APP_USE_FULL_SCREEN_INTENT settings: ${e.message}")
                }
            }
        }
    }

    private fun getTokenFirebase() {
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            try {
                if (task.isSuccessful) {
                    val token = task.result
                    if (!token.isNullOrEmpty()) {
                        tokenFirebase = token
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        resultWrapper = ResultWrapper(result)
        when (call.method) {
            Methods.ISUSERCONNECTED.value -> isUserConnected(call)
            Methods.USERDISPLAYNAME.value -> userDisplayName(call)
            Methods.CONNECT.value -> connect(call)
            Methods.DISCONNECT.value -> disconnect(call)
            Methods.STARTCALL.value -> startCall(call)
            Methods.GETHOTLINE.value -> getHotline(call)
            Methods.ANSWER.value -> answer(call)
            Methods.HANGUP.value -> hangUp(call)
            Methods.MUTE.value -> mute(call)
            Methods.SPEAKER.value -> speaker(call)
            Methods.SENDDTMF.value -> sendDTMF(call)
            Methods.HOLD.value -> hold(call)
            else -> resultWrapper?.notImplemented()
        }
    }

    private fun isUserConnected(call: MethodCall) {
        val isConnected = if (clientExists()) {
            client.isUserConnected() || client.getStateAccount() == AccountRegistrationState.Ok
        } else false
        resultWrapper?.success(mapOf("isUserConnected" to isConnected))
    }

    private fun userDisplayName(call: MethodCall) {
        val displayName = if (clientExists()) {
            val name = client.userDisplayName()
            if (!name.isNullOrEmpty()) name else client.getAccountUsername() ?: ""
        } else ""
        resultWrapper?.success(mapOf("userDisplayName" to displayName))
    }

    private fun connect(call: MethodCall) {
        val args = call.arguments as? Map<*, *>
        val token = (args?.get("token") ?: "") as String
        val envStr = (args?.get("environment") ?: "") as String
        val baseUrl = (args?.get("baseUrl") ?: "") as String

        val environment = try {
            VBotEnvironment.valueOf(envStr)
        } catch (_: Exception) {
            VBotEnvironment.PRODUCTION
        }
        val customUrl = if (baseUrl.isNotEmpty()) baseUrl else null
        val config = VBotConfig(environment, customUrl)
        client.setup(config)

        val fcm = if (tokenFirebase.isNotEmpty()) tokenFirebase else "dummy_fcm_token_sample"
        Log.d("VBotPhone", "connect: token length=${token.length}, env=$envStr, customUrl=$customUrl, fcmToken=$fcm")

        client.connect(token, fcm, VBotCompletion { displayName, error ->
            runOnUiThread {
                if (error == null) {
                    Log.d("VBotPhone", "connect SUCCESS: displayName=$displayName")
                    resultWrapper?.success(mapOf("displayName" to (displayName ?: "")))
                } else {
                    Log.d("VBotPhone", "connect ERROR: code=${error.code}, message=${error.message}")
                    resultWrapper?.error(error.code.toString(), error.message, null)
                }
            }
        })
    }

    private fun disconnect(call: MethodCall) {
        client.disconnect(VBotCompletion { _, error ->
            runOnUiThread {
                if (error == null) {
                    resultWrapper?.success(mapOf("disconnect" to true))
                } else {
                    resultWrapper?.error(error.code.toString(), error.message, null)
                }
            }
        })
    }

    private fun startCall(call: MethodCall) {
        val args = call.arguments as? Map<*, *>
        val phoneNumber = (args?.get("phoneNumber") ?: "") as String
        val hotline = (args?.get("hotline") ?: "") as String

        nameCall = phoneNumber
        isIncoming = false

        client.startOutgoingCall(
            hotline,
            phoneNumber,
            "",
            VBotCompletion { _, error ->
                runOnUiThread {
                    if (error == null) {
                        resultWrapper?.success(mapOf("phoneNumber" to phoneNumber))
                    } else {
                        resultWrapper?.error(error.code.toString(), error.message, null)
                    }
                }
            }
        )
    }

    private fun getHotline(call: MethodCall) {
        CoroutineScope(Dispatchers.IO).launch {
            val list = client.getHotlines()
            runOnUiThread {
                if (list != null) {
                    val listMap = arrayListOf<Map<String, String>>()
                    for (i in list) {
                        listMap.add(mapOf("name" to i.name, "phoneNumber" to i.phoneNumber))
                    }
                    resultWrapper?.success(listMap)
                } else {
                    resultWrapper?.error("ERROR", "Failed to get hotlines", null)
                }
            }
        }
    }

    private fun answer(call: MethodCall) {
        answerIncomingCallWhenReady()
        resultWrapper?.success(null)
    }

    /**
     * FCM can arrive before the SIP INVITE has created the SDK call object. The
     * native incoming-call screen waits for that object before answering; keep
     * the Flutter bridge on the same contract.
     */
    private fun answerIncomingCallWhenReady() {
        if (isWaitingToAnswer) return
        isWaitingToAnswer = true

        val handler = Handler(Looper.getMainLooper())
        var attempts = 0
        val answerWhenReady = object : Runnable {
            override fun run() {
                if (client.hasActiveCall()) {
                    isWaitingToAnswer = false
                    client.answerCall()
                } else if (attempts < 30) {
                    attempts++
                    handler.postDelayed(this, 500)
                } else {
                    isWaitingToAnswer = false
                }
            }
        }
        handler.post(answerWhenReady)
    }

    private fun hangUp(call: MethodCall) {
        client.endCall()
        resultWrapper?.success(null)
    }

    private fun mute(call: MethodCall) {
        isMute = !isMute
        // Following VBot-Android reference app: use AudioManager directly
        // Do NOT use client.muteCall() as it has inverted internal logic
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.isMicrophoneMute = isMute
            Log.d("VBotPhone", "mute toggled: isMute=$isMute, audioManager.isMicrophoneMute=${audioManager.isMicrophoneMute}")
        } catch (e: Exception) {
            Log.e("VBotPhone", "Error setting isMicrophoneMute: ${e.message}")
        }
        val callSink = CallSink(
            nameCall,
            currentCallState,
            isIncoming,
            isMute,
            onHold
        )
        events?.success(callSink.toMap())
        resultWrapper?.success(null)
    }

    private fun speaker(call: MethodCall) {
        isSpeaker = !isSpeaker
        client.onOffSpeaker(isSpeaker)
        Log.d("VBotPhone", "speaker toggled: isSpeaker=$isSpeaker")
        resultWrapper?.success(null)
    }

    private fun sendDTMF(call: MethodCall) {
        val value = ((call.arguments as? Map<*, *>)?.get("value") ?: "") as String
        client.sendDTMF(value)
        resultWrapper?.success(null)
    }

    private fun hold(call: MethodCall) {
        onHold = !onHold
        resultWrapper?.success(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        MainActivity.events = events
        // Nếu có cuộc gọi đang active, emit trạng thái hiện tại cho Flutter
        emitCurrentCallState()
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }
}

open class CallSink(
    var name: String,
    var state: String,
    var isIncoming: Boolean,
    var isMute: Boolean,
    var onHold: Boolean,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "name" to name,
        "state" to state,
        "isIncoming" to isIncoming,
        "isMute" to isMute,
        "onHold" to onHold,
    )
}

class ResultWrapper(private var result: MethodChannel.Result?) {
    fun success(data: Any?) {
        result?.success(data)
        result = null
    }

    fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        result?.error(errorCode, errorMessage, errorDetails)
        result = null
    }

    fun notImplemented() {
        result?.notImplemented()
        result = null
    }
}
