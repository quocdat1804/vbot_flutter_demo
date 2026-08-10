# Tài Liệu Viết Lại vbot_flutter_example — Phần Android

> Tài liệu này hướng dẫn sửa phần **Android native** trong `vbot_flutter_example` để tích hợp đúng chuẩn với [VBotPhone-Android-Public](file:///Users/namhoang/Documents/GitHub/mini-app/trustconnect/VBotPhone-Android-Public) SDK **v1.1.2**.
>
> Tham khảo tài liệu chính thức: [VBot Android SDK Documentation](https://vbotdevteam.github.io/vbot-documentation/android-sdk/cau-hinh-sdk.html)

---

## Mục Lục

1. [Tổng Quan Kiến Trúc Android SDK](#1-tổng-quan-kiến-trúc-android-sdk)
2. [Cấu Hình Gradle & Dependencies](#2-cấu-hình-gradle--dependencies)
3. [AndroidManifest.xml](#3-androidmanifestxml)
4. [MainActivity — MethodChannel Bridge](#4-mainactivity--methodchannel-bridge)
5. [FirebaseService — FCM Push Notification](#5-firebaseservice--fcm-push-notification)
6. [CallSink & ResultWrapper — Helper Classes](#6-callsink--resultwrapper--helper-classes)
7. [Dart Side — Flutter Code Tương Ứng](#7-dart-side--flutter-code-tương-ứng)
8. [Checklist Kiểm Tra](#8-checklist-kiểm-tra)

---

## 1. Tổng Quan Kiến Trúc Android SDK

### SDK Public API (v1.1.2)

SDK Android cung cấp class chính `VBotClient` tại package `com.vpmedia.sdkvbot.client`:

| Class/Interface | Mô tả |
|---|---|
| `VBotClient(context)` | Class chính, khởi tạo với Context |
| `VBotConfig` | Cấu hình: `environment`, `customBaseUrl` |
| `VBotEnvironment` | Enum: `PRODUCTION`, `STAGING`, `SANDBOX` |
| `ClientListener` | Open class lắng nghe events |
| `AccountRegistrationState` | Enum: Progress, Ok, Error, None |
| `CallState` | Enum: Null, Calling, Incoming, Early, Connecting, Confirmed, Disconnected |
| `VBotEndCallReason` | Enum nguyên nhân kết thúc cuộc gọi (dùng chung với iOS) |
| `VBotCallEndParty` | Enum bên kết thúc: caller, callee, system, server, carrier, unknown |
| `Hotline` | Data class: name, phoneNumber |

### Luồng hoạt động chính

```
┌─────────────────────────────────────────────────────────────────┐
│ Flutter (Dart)                                                  │
│  VBotPhoneManager ← MethodChannel → MainActivity (Kotlin)      │
│                   ← EventChannel  → events sink (call states)   │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴──────────┐
                    │  VBotClient (SDK)   │
                    │  - setup()          │
                    │  - connect()        │
                    │  - startOutgoingCall│
                    │  - endCall()        │
                    │  - muteCall()       │
                    │  - onSpeaker()      │
                    │  - getHotlines()    │
                    │  - disconnect()     │
                    └────────────────────┘
```

---

## 2. Cấu Hình Gradle & Dependencies

### File: `android/settings.gradle`

> [!IMPORTANT]
> SDK v1.1.0+ đổi repository từ JitPack sang GitHub raw. Phải cập nhật URL.

```groovy
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url 'https://raw.githubusercontent.com/VBotDevTeam/VBotPhoneSDKAndroid-Public/main/' }
    }
}
```

> [!WARNING]
> Nếu project dùng cấu trúc cũ (`build.gradle` root), thêm vào `allprojects.repositories`:
> ```groovy
> allprojects {
>     repositories {
>         google()
>         mavenCentral()
>         maven { url 'https://raw.githubusercontent.com/VBotDevTeam/VBotPhoneSDKAndroid-Public/main/' }
>     }
> }
> ```

### File: `android/app/build.gradle`

```groovy
plugins {
    id 'com.google.gms.google-services'
}

dependencies {
    // ★ VBot SDK — chỉ 1 dòng duy nhất (SDK v1.1.0+ đóng gói hết dependencies)
    implementation 'com.github.VBotDevTeam:VBotPhoneSDKAndroid-Public:1.1.2'

    // Firebase (cho Push Notification)
    implementation platform('com.google.firebase:firebase-bom:32.4.0')
    implementation 'com.google.firebase:firebase-messaging-ktx:23.3.1'
}
```

> [!CAUTION]
> **Nâng cấp từ v1.0.x:** Xoá toàn bộ các dòng khai báo thủ công: `rxjava`, `gson`, `retrofit`, `okhttp`, `reactive-streams`, `timber`, `spongycastle`, `security-crypto` — và mọi `exclude group: 'com.squareup.okio'`. SDK v1.1.0+ đóng gói tất cả dưới namespace `com.vpmedia.sdkvbot.shaded.*` để tránh xung đột.

### Cấu hình khác

```groovy
android {
    namespace "com.vpmedia.vbotsdksample"
    compileSdkVersion 34

    defaultConfig {
        applicationId "com.vpmedia.vbotsdksample"
        minSdkVersion 23      // ← SDK yêu cầu min 23
        targetSdkVersion 34
    }
}
```

---

## 3. AndroidManifest.xml

### File: `android/app/src/main/AndroidManifest.xml`

SDK tự khai báo 3 quyền: `DISABLE_KEYGUARD`, `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`.

App **phải** tự khai báo:

```xml
<!-- Bắt buộc -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

Components trong `<application>`:

```xml
<!-- Firebase Messaging Service -->
<service
    android:name=".FirebaseService"
    android:exported="false"
    android:stopWithTask="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

> [!NOTE]
> SDK tự khai báo `NotificationActivity` trong manifest của nó. Bạn **không cần** khai báo lại.
> Không cần khai báo `CallActivity` riêng nữa — SDK v1.1.2 tự quản lý notification incoming call.

---

## 4. MainActivity — MethodChannel Bridge

### File: `android/app/src/main/kotlin/.../MainActivity.kt`

Đây là file **quan trọng nhất**, là cầu nối giữa Flutter Dart và Android SDK.

### 4.1. Channel Names

```kotlin
object ChannelName {
    const val VBOT_CHANNEL = "com.vpmedia.vbot-sdk/vbot_phone"          // MethodChannel
    const val CALL_STATE_CHANNEL = "com.vpmedia.vbot-sdk/call"          // EventChannel
}
```

> [!IMPORTANT]
> Tên channel **phải khớp** với phía Dart trong `VBotPhoneManager`:
> - MethodChannel: `com.vpmedia.vbot-sdk/vbot_phone`
> - EventChannel: `com.vpmedia.vbot-sdk/call`

### 4.2. Methods Enum

```kotlin
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
```

### 4.3. Khởi tạo VBotClient (companion object)

```kotlin
companion object {
    @SuppressLint("StaticFieldLeak")
    lateinit var client: VBotClient
    var events: EventChannel.EventSink? = null
    var nameCall = ""
    var isIncoming = false
    var isMute = false
    var isSpeaker = false
    var onHold = false

    fun clientExists(): Boolean = ::client.isInitialized

    fun initClient(context: Context) {
        if (clientExists()) return
        client = VBotClient(context)
        client.setup()   // Cấu hình mặc định (PRODUCTION)
    }
}
```

> [!IMPORTANT]
> **Luồng khởi tạo SDK (v1.1.2):**
> 1. `VBotClient(context)` — constructor, load native libraries (pjsip)
> 2. `client.setup()` hoặc `client.setup(VBotConfig(...))` — tạo SIP endpoint
> 3. `client.addListener(listener)` — đăng ký listener
> 4. `client.connect(token, fcmToken) { ... }` — kết nối (async, completion handler)

### 4.4. ClientListener — Lắng nghe events từ SDK

```kotlin
private var listener = object : ClientListener() {
    // Kết nối tài khoản thành công
    override fun onUserConnected(displayName: String) {
        // displayName là tên hiển thị tài khoản
    }

    // Trạng thái đăng ký SIP thay đổi
    override fun onAccountRegistrationState(status: AccountRegistrationState, reason: String) {
        // status: None, Ok, Error, Progress
    }

    // Trạng thái cuộc gọi thay đổi → gửi qua EventChannel
    override fun onCallState(state: CallState) {
        runOnUiThread {
            val stateCall = when (state) {
                CallState.Null -> "none"
                CallState.Calling, CallState.Early -> "calling"
                CallState.Incoming -> "incoming"
                CallState.Connecting -> "connecting"
                CallState.Confirmed -> "confirmed"
                else -> "disconnected"
            }
            val callSink = CallSink(nameCall, stateCall, isIncoming, isMute, onHold)
            events?.success(callSink.toMap())
        }
    }

    // Cuộc gọi kết thúc — nguyên nhân và bên kết thúc
    override fun onCallEnded(reason: VBotEndCallReason, endedBy: VBotCallEndParty) {
        // reason.code / reason.key / reason.description
        // endedBy: caller, callee, system, server, carrier, unknown
    }

    // Fire khi có cuộc gọi ĐẾN — dùng để map với hệ thống của bạn
    override fun onExternalCallId(externalCallId: String) {}

    // Trạng thái mic thay đổi
    override fun onCallMuteStateChanged(muted: Boolean) {
        isMute = muted
    }

    // Mất kết nối socket
    override fun onNetworkUnreachable() {}

    // Lỗi phát sinh
    override fun onErrorCode(erCode: Int, message: String) {
        resultWrapper?.error(erCode.toString(), message, null)
    }
}
```

> [!IMPORTANT]
> **Mapping CallState (SDK → Flutter):**
>
> | SDK `CallState` | Flutter `state` string |
> |---|---|
> | `Null` | `"none"` |
> | `Calling` / `Early` | `"calling"` |
> | `Incoming` | `"incoming"` |
> | `Connecting` | `"connecting"` |
> | `Confirmed` | `"confirmed"` |
> | `Disconnected` | `"disconnected"` |

### 4.5. configureFlutterEngine — Setup channels

```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    initClient(context)
    client.addListener(listener)
    getTokenFirebase()

    GeneratedPluginRegistrant.registerWith(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VBOT_CHANNEL)
        .setMethodCallHandler(this)

    EventChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_STATE_CHANNEL)
        .setStreamHandler(this)

    // Request permissions
    requestCallPermissions()
}

private fun requestCallPermissions() {
    val needed = mutableListOf(Manifest.permission.RECORD_AUDIO)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        needed.add(Manifest.permission.POST_NOTIFICATIONS)
    }
    permissionLauncher.launch(needed.toTypedArray())
}
```

### 4.6. Method Handlers — Xử lý từng method call

#### `isUserConnected`
```kotlin
private fun isUserConnected(call: MethodCall, result: MethodChannel.Result) {
    val isConnected = client.getStateAccount() == AccountRegistrationState.Ok
    result.success(mapOf("isUserConnected" to isConnected))
}
```

#### `userDisplayName`
```kotlin
private fun userDisplayName(call: MethodCall, result: MethodChannel.Result) {
    val displayName = client.getAccountUsername()
    result.success(mapOf("userDisplayName" to displayName))
}
```

#### `connect`
```kotlin
private fun connect(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val token = (args?.get("token") ?: "") as String
    val envStr = (args?.get("environment") ?: "") as String
    val baseUrl = (args?.get("baseUrl") ?: "") as String

    // Cấu hình môi trường & Base URL trước khi connect
    val environment = try {
        VBotEnvironment.valueOf(envStr)
    } catch (_: Exception) {
        VBotEnvironment.PRODUCTION
    }
    val customUrl = if (baseUrl.isNotEmpty()) baseUrl else null
    val config = VBotConfig(environment, customUrl)
    client.setup(config)

    // v1.1.2: connect() dùng completion handler
    client.connect(token, tokenFirebase) { displayName, error ->
        runOnUiThread {
            if (error == null) {
                result.success(mapOf("displayName" to displayName))
            } else {
                result.error(error.code.toString(), error.message, null)
            }
        }
    }
}
```

> [!IMPORTANT]
> **Thay đổi so với v1.0.x:**
> - v1.0.x: `client.connect(token, firebase)` — kết quả qua `ClientListener.onAccountRegistrationState`, cần `ResultWrapper`
> - v1.1.2: `client.connect(token, firebase) { displayName, error -> }` — **completion handler**, trả kết quả 1 lần

#### `disconnect`
```kotlin
private fun disconnect(call: MethodCall, result: MethodChannel.Result) {
    client.disconnect { _, error ->
        runOnUiThread {
            if (error == null) {
                result.success(mapOf("disconnect" to true))
            } else {
                result.error(error.code.toString(), error.message, null)
            }
        }
    }
}
```

> [!WARNING]
> **Thay đổi so với v1.0.x:** `disconnect()` giờ là **async** với completion handler, không còn trả `Boolean` sync.

#### `startCall`
```kotlin
private fun startCall(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val name = (args?.get("name") ?: "") as String
    val phoneNumber = (args?.get("phoneNumber") ?: "") as String
    val hotline = (args?.get("hotline") ?: "") as String

    nameCall = phoneNumber
    isIncoming = false

    // v1.1.2: đổi từ startCall() sang startOutgoingCall() với completion
    client.startOutgoingCall(
        hotline = hotline,
        phone = phoneNumber,
        externalCallId = null
    ) { error ->
        runOnUiThread {
            if (error == null) {
                result.success(mapOf("phoneNumber" to phoneNumber))
            } else {
                result.error(error.code.toString(), error.message, null)
            }
        }
    }
}
```

> [!IMPORTANT]
> **Thay đổi so với v1.0.x:**
> - v1.0.x: `client.startCall(hotline, phone)` — sync
> - v1.1.2: `client.startOutgoingCall(hotline, phone, externalCallId) { error -> }` — async, completion handler
> - `externalCallId`: tùy chọn, tối đa 32 ký tự `[a-z0-9]`, gửi kèm header `X-exc-id`

#### `getHotlines`
```kotlin
private fun getHotline(call: MethodCall, result: MethodChannel.Result) {
    CoroutineScope(Dispatchers.IO).launch {
        val list = client.getHotlines()
        runOnUiThread {
            if (list != null) {
                val listMap = arrayListOf<Map<String, String>>()
                for (i in list) {
                    listMap.add(mapOf("name" to i.name, "phoneNumber" to i.phoneNumber))
                }
                result.success(listMap)
            } else {
                result.error("ERROR", "Failed to get hotlines", null)
            }
        }
    }
}
```

> [!WARNING]
> `getHotlines()` là **suspend function** (coroutine). Phải gọi trong coroutine scope. Trả `null` nếu lỗi.

#### `answer` / `hangup` / `mute` / `speaker` / `sendDTMF` / `hold`

```kotlin
private fun answer(call: MethodCall, result: MethodChannel.Result) {
    client.answerCall()
    result.success(null)  // ← BẮT BUỘC: trả result
}

private fun hangUp(call: MethodCall, result: MethodChannel.Result) {
    client.endCall()
    result.success(null)  // ← BẮT BUỘC: trả result
}

private fun mute(call: MethodCall, result: MethodChannel.Result) {
    isMute = !isMute
    client.muteCall(isMute)       // muteCall(enable: Bool) — truyền bool
    result.success(null)          // ← BẮT BUỘC: trả result
}

private fun speaker(call: MethodCall, result: MethodChannel.Result) {
    isSpeaker = !isSpeaker
    client.onSpeaker(isSpeaker)   // v1.1.2: đổi từ onOffSpeaker → onSpeaker
    result.success(null)          // ← BẮT BUỘC: trả result
}

private fun sendDTMF(call: MethodCall, result: MethodChannel.Result) {
    val value = ((call.arguments as? Map<*, *>)?.get("value") ?: "") as String
    client.sendDTMF(value)
    result.success(null)
}

private fun hold(call: MethodCall, result: MethodChannel.Result) {
    onHold = !onHold
    // SDK v1.1.2 chưa có API hold riêng — xử lý tùy theo SDK version
    result.success(null)
}
```

> [!CAUTION]
> **BẮT BUỘC** gọi `result.success(null)` sau mỗi method, nếu không Flutter side sẽ **hang vĩnh viễn** chờ response.

> [!WARNING]
> **Thay đổi so với v1.0.x:**
> - `onOffSpeaker(enable)` đã **đổi tên** thành `onSpeaker(enable)` trong v1.1.2
> - `muteCall(enable)`: `true` = mute, `false` = unmute — giữ nguyên
> - `declineIncomingCall(isBusy)`: API mới để từ chối cuộc gọi đến (`true` = báo bận)

### 4.7. Helper Methods — Lấy thông tin cuộc gọi

SDK v1.1.2 cung cấp các helper methods:

```kotlin
client.callName()       // String — tên/URI người gọi đến
client.getDuration()    // Int? — thời lượng cuộc gọi (giây), null nếu chưa kết nối
client.hasActiveCall()  // Boolean — đang có cuộc gọi hoạt động
client.isCallMute()     // Boolean — đang mute
client.isSpeakerOn()    // Boolean — đang bật loa
```

---

## 5. FirebaseService — FCM Push Notification

### File: `android/app/src/main/kotlin/.../FirebaseService.kt`

> [!IMPORTANT]
> VBot SDK **không** tự khai báo `FirebaseMessagingService`. Bạn phải tự tạo và khai báo trong `AndroidManifest.xml`.

```kotlin
class FirebaseService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // Lưu token; truyền vào connect() ở lần kết nối kế tiếp
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val map = HashMap(remoteMessage.data)

        // Kiểm tra payload chứa key "transId" — đây là cuộc gọi VoIP
        if (map.containsKey("transId")) {
            VBotClient(applicationContext).apply {
                if (!isSetup()) setup(VBotConfig(VBotEnvironment.PRODUCTION))
                notificationCall(map)
            }
        }
        // Các loại push khác xử lý như bình thường
    }
}
```

> [!IMPORTANT]
> **Cách `notificationCall(map)` hoạt động (v1.1.2):**
> - `offCall == "0"`: Hiện notification cuộc gọi đến + chuẩn bị SIP. Nếu không register được trong **20 giây** → `onCallEnded(IncomingCallTimeout)` + tự dọn.
> - `offCall != "0"`: Cuộc gọi đã bị hủy từ xa → hủy chuẩn bị, gỡ notification.

> [!WARNING]
> **Nếu app đã có FirebaseMessagingService:** Android chỉ cho **một** service nhận `MESSAGING_EVENT`. Dùng service sẵn có, phân loại: nếu message chứa `transId` thì route sang `notificationCall(map)`, còn lại xử lý như cũ.

### Incoming call flow (v1.1.2)

```
FCM Push → FirebaseService.onMessageReceived → client.notificationCall(hashMap)
→ SDK hiện notification → User tap Accept → client.answerCall()
→ onCallState(Incoming) → EventChannel → Flutter
```

SDK tự quản lý notification — không cần tạo `CallActivity` riêng (khác v1.0.x).

Để từ chối cuộc gọi đến:
```kotlin
client.declineIncomingCall(isBusy = true)  // true = báo bận (Busy Here)
```

---

## 6. CallSink & ResultWrapper — Helper Classes

### CallSink

```kotlin
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
```

> [!IMPORTANT]
> Map keys **phải khớp** với `VBotSink.fromMap()` bên Dart:
> `name`, `state`, `isIncoming`, `isMute`, `onHold`

### ResultWrapper

```kotlin
class ResultWrapper(private var result: MethodChannel.Result?) {
    fun success(data: Any?) {
        result?.success(data)
        result = null
    }
    fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        result?.error(errorCode, errorMessage, errorDetails)
        result = null
    }
}
```

> [!NOTE]
> `ResultWrapper` đảm bảo `result` chỉ được gọi **1 lần** (tránh crash "Reply already submitted").
> Với SDK v1.1.2 dùng completion handler, `ResultWrapper` ít cần hơn — nhưng vẫn hữu ích cho `getHotlines` và các trường hợp listener callback.

---

## 7. Dart Side — Flutter Code Tương Ứng

### Tham chiếu nhanh method call ↔ SDK

| Dart `invokeMethod` | Android SDK method (v1.1.2) | Return type |
|---|---|---|
| `isUserConnected` | `client.getStateAccount()` | `Map { isUserConnected: bool }` |
| `userDisplayName` | `client.getAccountUsername()` | `Map { userDisplayName: String }` |
| `connect` | `client.connect(token, firebase) { displayName, error -> }` | `Map { displayName: String }` |
| `disconnect` | `client.disconnect { _, error -> }` | `Map { disconnect: bool }` |
| `startCall` | `client.startOutgoingCall(hotline, phone, externalCallId) { error -> }` | `Map { phoneNumber: String }` |
| `getHotlines` | `client.getHotlines()` (suspend) | `List<Map { name, phoneNumber }>` |
| `answer` | `client.answerCall()` | void |
| `hangup` | `client.endCall()` | void |
| `mute` | `client.muteCall(enable)` | void |
| `speaker` | `client.onSpeaker(enable)` | void |
| `sendDTMF` | `client.sendDTMF(digit)` | void |

### EventChannel data format (CallSink)

```dart
class VBotSink {
  final String name;       // Tên/số người gọi
  final String state;      // "none" | "calling" | "incoming" | "connecting" | "confirmed" | "disconnected"
  final bool isIncoming;   // true = incoming call
  final bool isMute;       // true = đang mute
  final bool onHold;       // true = đang hold
}
```

---

## 8. Checklist Kiểm Tra

### Gradle & Dependencies
- [ ] `settings.gradle` (hoặc `build.gradle` root) có `maven { url 'https://raw.githubusercontent.com/VBotDevTeam/VBotPhoneSDKAndroid-Public/main/' }`
- [ ] **KHÔNG** còn `maven { url 'https://jitpack.io' }` (cũ)
- [ ] `app/build.gradle` có dependency `com.github.VBotDevTeam:VBotPhoneSDKAndroid-Public:1.1.2`
- [ ] **KHÔNG** còn dependencies thừa (rxjava, okhttp, retrofit, gson, timber...)
- [ ] Firebase dependencies: `firebase-bom` + `firebase-messaging-ktx`
- [ ] `google-services.json` có trong `android/app/`
- [ ] `minSdkVersion` ≥ 23
- [ ] `compileSdkVersion` ≥ 34

### AndroidManifest.xml
- [ ] Có permissions: `INTERNET`, `RECORD_AUDIO`
- [ ] Khai báo `FirebaseService` với `MESSAGING_EVENT` intent-filter

### MainActivity.kt
- [ ] MethodChannel name = `"com.vpmedia.vbot-sdk/vbot_phone"` — khớp Dart
- [ ] EventChannel name = `"com.vpmedia.vbot-sdk/call"` — khớp Dart
- [ ] `connect()` dùng **completion handler** (v1.1.2), nhận `token`, `environment`, `baseUrl`
- [ ] `startCall()` gọi `client.startOutgoingCall(hotline, phone, externalCallId)` với completion
- [ ] `disconnect()` dùng **completion handler** (v1.1.2)
- [ ] `speaker()` gọi `client.onSpeaker(enable)` (không phải `onOffSpeaker`)
- [ ] Tất cả method handlers đều gọi `result.success()` hoặc `result.error()`
- [ ] `ClientListener` map đúng `CallState` → string
- [ ] `ClientListener` implement `onCallEnded`, `onCallMuteStateChanged`

### Push Notification
- [ ] `FirebaseService` xử lý payload chứa `transId` → route sang `notificationCall(map)`
- [ ] `notificationCall()` xử lý `offCall == "0"` (cuộc gọi đến) và `offCall != "0"` (cancel)

### Dart
- [ ] `CallSink.toMap()` keys khớp với `VBotSink.fromMap()`: `name`, `state`, `isIncoming`, `isMute`, `onHold`
- [ ] `home_page.dart` UI có Dropdown chọn Environment & ô Base URL
- [ ] Runtime permissions được request khi cần

---

## Phụ Lục: Changelog SDK Android

### v1.1.2 (03/08/2026)
- **Tính năng mới**: `onCallEnded(reason: VBotEndCallReason, endedBy: VBotCallEndParty)` — biết nguyên nhân và bên kết thúc
- **SIP Mapping**: Tự động map SIP response sang `VBotEndCallReason` (486 → `busy`/`callee`, 487 → `callerCanceled`/`caller`, 500 → `connectionError`/`server`)

### v1.1.1 (30/07/2026)
- **Đổi tên**: `EndCallReason` → `VBotEndCallReason`
- **CamelCase**: 23 case lỗi khớp iOS SDK (`Normal` → `normaly`, `Busy` → `busy`, `Unknown` → `unknownError`)
- **Mã lỗi**: `microphonePermissionDenied` đổi từ `999` sang `9999`

### v1.1.0 (26/07/2026)
- **Thin/Shaded AAR**: Đóng gói toàn bộ thư viện bên thứ 3 dưới `com.vpmedia.sdkvbot.shaded.*`
- **Repository**: Chuyển sang `raw.githubusercontent.com` (Maven tĩnh)
- **API mới**: `startOutgoingCall(...)`, `connect(...)` với completion handler, `disconnect(...)` async
- **Deprecated**: `startCall`, `connect` không completion, `disconnect(): Boolean`, `onOffSpeaker`

---

> [!TIP]
> Khi test, có thể dùng `VBotConfig(environment = VBotEnvironment.SANDBOX)` để test trên môi trường sandbox trước khi chuyển production.
