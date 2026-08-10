# Tài Liệu Viết Lại vbot_flutter_example — Phần iOS

> Tài liệu này hướng dẫn sửa phần **iOS native** trong `vbot_flutter_example` để tích hợp đúng chuẩn với [VBotPhone-iOS-Public](file:///Users/namhoang/Documents/GitHub/mini-app/trustconnect/VBotPhone-iOS-Public) SDK.

---

## Mục Lục

1. [Tổng Quan Kiến Trúc iOS SDK](#1-tổng-quan-kiến-trúc-ios-sdk)
2. [Cấu Hình Podfile & Dependencies](#2-cấu-hình-podfile--dependencies)
3. [AppDelegate — MethodChannel Bridge](#3-appdelegate--methodchannel-bridge)
4. [VBotPhoneDelegate — Lắng Nghe Events](#4-vbotphonedelegate--lắng-nghe-events)
5. [CallSink — Mapping Call State](#5-callsink--mapping-call-state)
6. [Dart Side — Flutter Code Tương Ứng](#6-dart-side--flutter-code-tương-ứng)
7. [Khác Biệt Giữa iOS và Android SDK](#7-khác-biệt-giữa-ios-và-android-sdk)
8. [Checklist Kiểm Tra](#8-checklist-kiểm-tra)

---

## 1. Tổng Quan Kiến Trúc iOS SDK

### SDK Public API

iOS SDK sử dụng pattern **Singleton + Delegate**:

| Class/Protocol | Mô tả |
|---|---|
| `VBotPhone.sharedInstance` | Singleton chính, entry point cho tất cả operations |
| `VBotConfig` | Cấu hình: supportPopupCall, includesCallsInRecents, iconTemplateImageData, environment, customBaseUrl |
| `VBotEnvironment` | Enum: `.production`, `.staging`, `.sandbox` |
| `VBotPhoneDelegate` | Protocol delegate nhận events (call state, mute, end call...) |
| `VBotCallState` | Enum: null, calling, incoming, early, connecting, confirmed, disconnected |
| `VBotEndCallReason` | Enum lý do kết thúc cuộc gọi (rất chi tiết) |
| `VBotHotline` | Class: name, phoneNumber |

### Luồng hoạt động chính

```
┌──────────────────────────────────────────────────────────────────┐
│ Flutter (Dart)                                                   │
│  VBotPhoneManager ← MethodChannel → AppDelegate (Swift)          │
│                   ← EventChannel  → eventSink (call states)      │
└──────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴──────────────┐
                    │  VBotPhone.sharedInstance│
                    │  - setup(with:)         │
                    │  - connect(token:...)   │
                    │  - startOutgoingCall()  │
                    │  - endCall()            │
                    │  - muteCall()           │
                    │  - onOffSpeaker()       │
                    │  - getHotlines()        │
                    │  - disconnect()         │
                    └────────────────────────┘
```

### Kiến trúc đặc biệt iOS

> [!IMPORTANT]
> iOS SDK khác Android ở nhiều điểm:
> - Dùng **Singleton** (`VBotPhone.sharedInstance`) thay vì tạo instance
> - Dùng **Delegate protocol** thay vì listener class
> - Tích hợp **CallKit** (hiện native call UI trên iOS)
> - Tích hợp **PushKit** (VoIP push, không dùng FCM)
> - Các method async dùng **completion handler** thay vì listener callback
> - SDK tự quản lý **CallKit UI** (call screen native)

---

## 2. Cấu Hình Podfile & Dependencies

### File: `ios/Podfile`

```ruby
platform :ios, '13.5'
source "https://github.com/CocoaPods/Specs.git"

target 'Runner' do
  use_frameworks!

  pod 'VBotPhoneSDKiOS-Public', '1.1.7'

  target 'RunnerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
    end
    if target.name == 'Starscream'
      target.build_configurations.each do |config|
        config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      end
    end
  end
end
```

> [!IMPORTANT]
> **Pod quan trọng:**
> - `VBotPhoneSDKiOS-Public` version `1.1.7` — SDK chính
> - Platform tối thiểu: `ios '13.5'`
> - Cần `use_frameworks!` vì SDK dùng Swift

### Import trong Swift

```swift
import VBotPhonePublic    // ← Framework name khi import
```

> [!WARNING]
> Tên import là `VBotPhonePublic` (không phải `VBotPhoneSDK` hay `VBotPhoneSDKiOS-Public`).

---

## 3. AppDelegate — MethodChannel Bridge

### File: `ios/Runner/AppDelegate.swift`

Đây là file **quan trọng nhất** phía iOS, đóng vai trò bridge giữa Flutter và SDK.

### 3.1. Channel Names & Methods Enum

```swift
enum ChannelName {
    static let VBOT_CHANNEL = "com.vpmedia.vbot-sdk/vbot_phone"
    static let CALL_STATE_CHANNEL = "com.vpmedia.vbot-sdk/call"
}

enum Methods: String {
    case ISUSERCONNECTED = "isUserConnected"
    case USERDISPLAYNAME = "userDisplayName"
    case CONNECT = "connect"
    case DISCONNECT = "disconnect"
    case STARTCALL = "startCall"
    case GETHOTLINE = "getHotlines"
    case HANGUP = "hangup"
    case MUTE = "mute"
    case SPEAKER = "speaker"
}
```

### 3.2. AppDelegate Class Declaration

```swift
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    let client = VBotPhone.sharedInstance
    // ...
}
```

> [!NOTE]
> AppDelegate implement `FlutterStreamHandler` cho EventChannel.

### 3.3. Setup trong didFinishLaunchingWithOptions

```swift
override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 1. Cấu hình VBot
    let config = VBotConfig(
        iconTemplateImageData: UIImage(named: "callkit-icon")?.pngData()
    )

    // 2. Setup SDK
    VBotPhone.sharedInstance.setup(with: config)

    // 3. Đăng ký delegate
    VBotPhone.sharedInstance.addDelegate(self)

    // 4. Setup Flutter channels
    let controller = window?.rootViewController as! FlutterViewController

    let vbotChannel = FlutterMethodChannel(
        name: ChannelName.VBOT_CHANNEL,
        binaryMessenger: controller.binaryMessenger
    )
    vbotChannel.setMethodCallHandler(self.methodCall)

    let chargingChannel = FlutterEventChannel(
        name: ChannelName.CALL_STATE_CHANNEL,
        binaryMessenger: controller.binaryMessenger
    )
    chargingChannel.setStreamHandler(self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

> [!IMPORTANT]
> **Luồng khởi tạo iOS SDK:**
> 1. `VBotConfig(...)` — tạo cấu hình
> 2. `VBotPhone.sharedInstance.setup(with: config)` — khởi tạo SIP, PushKit, CallKit
> 3. `VBotPhone.sharedInstance.addDelegate(self)` — đăng ký nhận events
>
> **VBotConfig parameters:**
> - `supportPopupCall`: Bool — cho phép popup call overlay (mặc định `false`)
> - `includesCallsInRecents`: Bool — hiện cuộc gọi trong lịch sử gọi (mặc định `false`)
> - `iconTemplateImageData`: Data? — icon hiện trên CallKit UI
> - `environment`: VBotEnvironment — `.production` (mặc định) / `.staging` / `.sandbox`
> - `customBaseUrl`: String? — URL tùy chỉnh (override environment URL)

### 3.4. Method Router

```swift
func methodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let mode = Methods(rawValue: call.method)
    switch mode {
    case .ISUSERCONNECTED:  self.isUserConnected(call, result)
    case .USERDISPLAYNAME:  self.userDisplayName(call, result)
    case .CONNECT:          self.connect(call, result)
    case .DISCONNECT:       self.disconnect(call, result)
    case .STARTCALL:        self.startCall(call, result)
    case .GETHOTLINE:       self.getHotlines(call, result)
    case .HANGUP:           self.hangup(call, result)
    case .MUTE:             self.mute(call, result)
    case .SPEAKER:          self.speaker(call, result)
    default:                result(FlutterMethodNotImplemented)
    }
}
```

### 3.5. Method Handlers — Chi tiết từng method

#### `isUserConnected`
```swift
func isUserConnected(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let isUserConnected = self.client.isUserConnected()
    result(["isUserConnected": isUserConnected])
}
```

> [!NOTE]
> iOS SDK kiểm tra bằng `isUserConnected()` (kiểm tra token đã lưu), khác Android dùng `getStateAccount()`.

#### `userDisplayName`
```swift
func userDisplayName(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let userDisplayName = self.client.userDisplayName()
    result(["userDisplayName": userDisplayName])
}
```

#### `connect`
```swift
func connect(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let token = (args?["token"] as? String ?? "")
    let envStr = (args?["environment"] as? String)
    let baseUrl = (args?["baseUrl"] as? String)

    // Cập nhật config nếu Dart truyền environment/baseUrl
    if envStr != nil || baseUrl != nil {
        var env: VBotEnvironment = .production
        switch envStr?.uppercased() {
        case "STAGING": env = .staging
        case "SANDBOX": env = .sandbox
        default: env = .production
        }
        let config = VBotConfig(environment: env, customBaseUrl: baseUrl)
        VBotPhone.sharedInstance.setConfig(config: config)
    }

    self.client.connect(token: token) { displayName, error in
        if let error = error as NSError? {
            result(FlutterError(
                code: "\(error.code)",
                message: error.localizedDescription,
                details: nil
            ))
            return
        }
        result(["displayName": displayName])
    }
}
```

> [!IMPORTANT]
> **Lưu ý:**
> - iOS `connect()` dùng **completion handler** → kết quả trả về trực tiếp qua `result`
> - iOS `connect()` signature: `connect(token:pushkitToken:completion:)` — SDK tự lấy PushKit token, từ Flutter chỉ cần truyền `token`
> - Dart truyền thêm `environment` và `baseUrl` → cần gọi `setConfig()` trước `connect()` để chuyển môi trường

#### `disconnect`
```swift
func disconnect(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    self.client.disconnect { error in
        if let error = error as NSError? {
            result(FlutterError(
                code: "\(error.code)",
                message: error.localizedDescription,
                details: nil
            ))
            return
        }
        result(["disconnect": true])
    }
}
```

#### `startCall`
```swift
func startCall(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let name = ((call.arguments as? [String: Any])?["name"] as? String ?? "")
    let phoneNumber = ((call.arguments as? [String: Any])?["phoneNumber"] as? String ?? "")
    let hotline = ((call.arguments as? [String: Any])?["hotline"] as? String ?? "")

    self.client.startOutgoingCall(
        name: name,
        number: phoneNumber,
        hotline: hotline
    ) { [weak self] resultAPI in
        switch resultAPI {
        case .success():
            result(["phoneNumber": phoneNumber])
        case .failure(let error):
            if let error = error as NSError? {
                result(FlutterError(
                    code: "\(error.code)",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }
}
```

> [!IMPORTANT]
> **So sánh với Android SDK v1.1.2:**
> - iOS: `startOutgoingCall(name:number:hotline:completion:)` — cần truyền `name` (displayName)
> - Android: `startOutgoingCall(hotline:phone:externalCallId:completion:)` — không cần name
> - Cả hai đều dùng **completion handler** (Android v1.1.2 đã đổi sang async)

#### `getHotlines`
```swift
func getHotlines(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    self.client.getHotlines { hotlines, error in
        if let error = error as NSError? {
            result(FlutterError(
                code: "\(error.code)",
                message: error.localizedDescription,
                details: nil
            ))
            return
        }
        let hotlinesMap = hotlines?.map { hotline in
            ["name": hotline.name, "phoneNumber": hotline.phoneNumber]
        }
        result(hotlinesMap)
    }
}
```

#### `hangup`
```swift
func hangup(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    self.client.endCall { error in
        if let error = error as NSError? {
            result(FlutterError(
                code: "\(error.code)",
                message: error.localizedDescription,
                details: nil
            ))
            return
        }
        result(nil)  // ← BẮT BUỘC: trả result khi thành công, nếu không Flutter sẽ hang
    }
}
```

#### `mute` / `speaker`
```swift
func mute(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    self.client.muteCall()     // Toggle, không cần truyền param
    result(nil)                // ← BẮT BUỘC: trả result
}

func speaker(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    self.client.onOffSpeaker() // Toggle, không cần truyền param
    result(nil)                // ← BẮT BUỘC: trả result
}
```

> [!WARNING]
> **Khác biệt so với Android:**
> - iOS `muteCall()` / `onOffSpeaker()` là **toggle** (không truyền bool)
> - Android `muteCall(enable)` / `onSpeaker(enable)` phải truyền **bool** (v1.1.2 đổi tên từ `onOffSpeaker` → `onSpeaker`)
> - **BẮT BUỘC** gọi `result(nil)` sau mỗi method, nếu không Flutter side sẽ **hang vĩnh viễn** chờ response

### 3.6. FlutterStreamHandler Implementation

```swift
func onListen(withArguments arguments: Any?,
              eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
}

func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
}
```

---

## 4. VBotPhoneDelegate — Lắng Nghe Events

### Extension AppDelegate conform VBotPhoneDelegate

```swift
extension AppDelegate: VBotPhoneDelegate {
    // Khi trạng thái cuộc gọi thay đổi
    func callStateChanged(state: VBotCallState) {
        guard let eventSink = eventSink else { return }
        eventSink(CallSink(state, name: self.client.getCallName()).toMap)
    }

    // Khi trạng thái mute thay đổi
    func callMuteStateDidChange(muted: Bool) {
        guard let eventSink = eventSink else { return }
        let callState = VBotPhone.sharedInstance.getCallState()
        eventSink(CallSink(callState, name: self.client.getCallName()).toMap)
    }

    // Khi cuộc gọi kết thúc (kèm bên kết thúc — từ SDK v1.1.7+)
    func callEnded(reason: VBotEndCallReason, endedBy: VBotCallEndParty) {
        print("callEnded reason: \(reason.description), endedBy: \(endedBy)")
    }
}
```

### Tất cả VBotPhoneDelegate methods (optional)

| Method | Khi nào được gọi |
|---|---|
| `callStateChanged(state:)` | Trạng thái cuộc gọi thay đổi |
| `callStarted()` | Cuộc gọi đi bắt đầu |
| `callAccepted()` | User chấp nhận incoming call |
| `callEnded(reason:endedBy:)` | Cuộc gọi kết thúc (với lý do + bên kết thúc) |
| `microphonePermission(status:)` | Trạng thái permission mic |
| `callMuteStateDidChange(muted:)` | Mute state thay đổi |
| `showCallVC()` | SDK yêu cầu hiện call screen |
| `returnToCallVC()` | SDK yêu cầu quay lại call screen |
| `hideCallVC()` | SDK yêu cầu ẩn call screen |
| `networkIsUnreachable()` | Mất mạng |
| `internetConnectionChanged()` | Mạng thay đổi |
| `didReceiveExternalCallId(_:)` | Nhận externalCallId |

> [!TIP]
> Tất cả methods đều **optional**. Bạn chỉ cần implement những gì cần thiết. Tối thiểu nên implement: `callStateChanged`, `callMuteStateDidChange`, `callEnded`.

---

## 5. CallSink — Mapping Call State

### Struct CallSink

```swift
struct CallSink {
    let name: String
    let state: String
    let isIncoming: Bool
    let isMute: Bool
    let onHold: Bool

    init(_ callState: VBotCallState, name: String) {
        self.name = name
        self.state = CallSink.getCallState(callState)
        self.isIncoming = VBotPhone.sharedInstance.isIncomingCall()
        self.isMute = VBotPhone.sharedInstance.isCallMute()
        self.onHold = VBotPhone.sharedInstance.isCallHold()
    }

    public static func getCallState(_ state: VBotCallState) -> String {
        switch state {
        case .calling, .early:    return "calling"
        case .incoming:           return "incoming"
        case .connecting:         return "connecting"
        case .confirmed:          return "confirmed"
        default:                  return "disconnected"
        }
    }

    var toMap: [String: Any] {
        return [
            "name": self.name,
            "state": self.state,
            "isIncoming": self.isIncoming,
            "isMute": self.isMute,
            "onHold": self.onHold
        ]
    }
}
```

> [!IMPORTANT]
> **Mapping VBotCallState (SDK → Flutter):**
>
> | SDK `VBotCallState` | Flutter `state` string |
> |---|---|
> | `.null` | `"disconnected"` (default) |
> | `.calling` / `.early` | `"calling"` |
> | `.incoming` | `"incoming"` |
> | `.connecting` | `"connecting"` |
> | `.confirmed` | `"confirmed"` |
> | `.disconnected` | `"disconnected"` |

> [!NOTE]
> Map keys **phải khớp** với `VBotSink.fromMap()` bên Dart: `name`, `state`, `isIncoming`, `isMute`, `onHold`

### Các helper methods iOS SDK dùng trong CallSink

```swift
VBotPhone.sharedInstance.isIncomingCall()  // Bool - có phải incoming call không
VBotPhone.sharedInstance.isCallMute()      // Bool - cuộc gọi có mute không
VBotPhone.sharedInstance.isCallHold()      // Bool - cuộc gọi có hold không
VBotPhone.sharedInstance.getCallName()     // String - tên người gọi
VBotPhone.sharedInstance.getCallState()    // VBotCallState - trạng thái hiện tại
```

---

## 6. Dart Side — Flutter Code Tương Ứng

### Tham chiếu nhanh method call ↔ SDK

| Dart `invokeMethod` | iOS SDK method | Return type |
|---|---|---|
| `isUserConnected` | `client.isUserConnected()` | `Map { isUserConnected: bool }` |
| `userDisplayName` | `client.userDisplayName()` | `Map { userDisplayName: String? }` |
| `connect` | `client.connect(token:completion:)` | `Map { displayName: String? }` |
| `disconnect` | `client.disconnect(completion:)` | `Map { disconnect: bool }` |
| `startCall` | `client.startOutgoingCall(name:number:hotline:completion:)` | `Map { phoneNumber: String }` |
| `getHotlines` | `client.getHotlines(completion:)` | `List<Map { name, phoneNumber }>` |
| `hangup` | `client.endCall(completion:)` | void |
| `mute` | `client.muteCall()` | void |
| `speaker` | `client.onOffSpeaker()` | void |

### EventChannel data format

Giống Android — cùng format `VBotSink`:

```dart
class VBotSink {
  final String name;       // Tên/số người gọi
  final String state;      // "calling" | "incoming" | "connecting" | "confirmed" | "disconnected"
  final bool isIncoming;   // true = incoming call
  final bool isMute;       // true = đang mute
  final bool onHold;       // true = đang hold
}
```

---

## 7. Khác Biệt Giữa iOS và Android SDK (Android v1.1.2)

> [!CAUTION]
> Đây là bảng tổng hợp **quan trọng** cần nắm khi viết code Flutter cho cả 2 platform.
> Android SDK v1.1.2 đã thay đổi đáng kể so với v1.0.12 — hội tụ gần hơn với iOS về pattern.

| Đặc điểm | Android SDK v1.1.2 | iOS SDK v1.1.7 |
|---|---|---|
| **Pattern** | Instance (`VBotClient(context)`) | Singleton (`VBotPhone.sharedInstance`) |
| **Events** | `ClientListener` (open class) | `VBotPhoneDelegate` (protocol) |
| **Import** | `com.vpmedia.sdkvbot.client.*` | `import VBotPhonePublic` |
| **Push** | Firebase Cloud Messaging (FCM) | PushKit (VoIP push) |
| **Call UI** | SDK hiện notification, app tự build UI | CallKit (native iOS) |
| **connect()** | `connect(token, fcmToken) { displayName, error -> }` | `connect(token:) { displayName, error in }` |
| **startCall** | `startOutgoingCall(hotline:phone:externalCallId:) { error -> }` | `startOutgoingCall(name:number:hotline:completion:)` |
| **mute** | `muteCall(enable: Bool)` — truyền bool | `muteCall()` — toggle |
| **speaker** | `onSpeaker(enable: Bool)` — truyền bool | `onOffSpeaker()` — toggle |
| **disconnect** | `disconnect { _, error -> }` — async | `disconnect { error in }` — async |
| **endCall** | `endCall()` — sync | `endCall { error in }` — async |
| **getHotlines** | Suspend (coroutine) | Completion handler |
| **Config** | `VBotConfig(environment, customBaseUrl)` | `VBotConfig(supportPopupCall:includesCallsInRecents:iconTemplateImageData:environment:customBaseUrl:)` |
| **Incoming call** | FCM → `notificationCall(hashMap)` → SDK hiện notification | PushKit → SDK tự xử lý → CallKit UI |
| **End call reason** | `onCallEnded(reason, endedBy)` | `callEnded(reason:endedBy:)` |
| **Repository** | `maven { url 'https://raw.githubusercontent.com/.../main/' }` | CocoaPods |
| **Dependencies** | Chỉ 1 dòng (SDK đóng gói hết) | `pod 'VBotPhoneSDKiOS-Public'` |

### Xử lý incoming call — Khác nhau hoàn toàn

**Android (v1.1.2):**
```
FCM Push → FirebaseService.onMessageReceived → client.notificationCall(hashMap)
→ SDK hiện notification → User tap → client.answerCall()
→ onCallState(Incoming) → EventChannel → Flutter
```
- `notificationCall(map)` xử lý tự động: `offCall == "0"` hiện notification, `offCall != "0"` hủy.
- Nếu không register SIP trong 20s → `onCallEnded(IncomingCallTimeout)` + tự dọn.

**iOS:**
```
PushKit VoIP Push → SDK tự xử lý → CallKit UI (native) → SDK callback delegate
→ callStateChanged → EventChannel → Flutter
```

> [!IMPORTANT]
> iOS **không cần** xử lý push notification riêng trong Flutter app. SDK tự đăng ký PushKit và xử lý incoming call qua CallKit. Flutter chỉ cần lắng nghe `callStateChanged` qua EventChannel.

---

## 8. Checklist Kiểm Tra

- [ ] `ios/Podfile` có `pod 'VBotPhoneSDKiOS-Public', '1.1.7'`
- [ ] `ios/Podfile` platform ≥ `'13.5'`
- [ ] `ios/Podfile` có `use_frameworks!`
- [ ] Đã chạy `pod install` thành công
- [ ] `AppDelegate.swift` import `VBotPhonePublic`
- [ ] `AppDelegate.swift` conform `FlutterStreamHandler`
- [ ] `AppDelegate.swift` conform `VBotPhoneDelegate`
- [ ] `VBotPhone.sharedInstance.setup(with: config)` được gọi trong `didFinishLaunchingWithOptions`
- [ ] `VBotPhone.sharedInstance.addDelegate(self)` được gọi
- [ ] MethodChannel name = `"com.vpmedia.vbot-sdk/vbot_phone"` — khớp với Dart
- [ ] EventChannel name = `"com.vpmedia.vbot-sdk/call"` — khớp với Dart
- [ ] `callStateChanged` delegate gửi event qua `eventSink`
- [ ] `callMuteStateDidChange` delegate gửi event qua `eventSink`
- [ ] `CallSink.toMap` keys khớp với Dart `VBotSink.fromMap()` (`name`, `state`, `isIncoming`, `isMute`, `onHold`)
- [ ] `connect()` truyền đúng token, handle completion
- [ ] `startCall()` truyền đúng `name`, `phoneNumber`, `hotline`
- [ ] `muteCall()` / `onOffSpeaker()` gọi **không param** (toggle)
- [ ] Xcode project có **Push Notifications** capability
- [ ] Xcode project có **Voice over IP** background mode
- [ ] Có `callkit-icon` image trong Assets (nếu cần)
- [ ] Info.plist có `NSMicrophoneUsageDescription`

### Xcode Capabilities cần bật

1. **Push Notifications** — để nhận VoIP push
2. **Background Modes:**
   - Voice over IP
   - Remote notifications
   - Background fetch (optional)

---

## Phụ Lục: VBotEndCallReason (Dùng chung iOS + Android)

Cả iOS và Android SDK (v1.1.2+) đều dùng chung bảng mã `VBotEndCallReason`:

| Key / Enum case | Code | Mô tả |
|---|---|---|
| `normaly` | 1000 | Kết thúc bình thường |
| `busy` | 1001 | Máy bận |
| `timeOut` | 1004 | Timeout |
| `noPushToken` | 1018 | Chưa đăng ký push notification |
| `notReadyForStartCall` | 2002 | Chưa sẵn sàng |
| `invalidPhoneNumber` | 2004 | Số điện thoại không hợp lệ |
| `noDataFromServer` | 2005 | Không có data từ server |
| `endCallBeforeServerStartCall` | 2006 | Kết thúc trước khi server bắt đầu |
| `noCallCreated` / `noSIPCallCreated` | 2007 | Không tạo được cuộc gọi |
| `dataInvalid` | 2008 | Data không hợp lệ |
| `noVBotUser` / `noVBotSIPUser` | 2009 | Không có thông tin tài khoản |
| `authenticatedFailed` | 2010 | Xác thực thất bại |
| `anotherCallInProgress` | 2011 | Đang có cuộc gọi khác |
| `decline` | 2013 | Từ chối cuộc gọi |
| `temporarilyUnavailable` | 2014 | Không liên lạc được |
| `reportNewIncomingCallFailed` | 2016 | Không thể tiếp nhận cuộc gọi đến |
| `alertDataNotFound` | 2017 | Dữ liệu thông báo không hợp lệ |
| `setupEndpointFailed` | 2019 | Khởi tạo dịch vụ gọi thất bại |
| `requestCallKitActionFailed` | 2020 | Thực thi hành động cuộc gọi thất bại |
| `noAccount` | 2022 | Tài khoản chưa được cấu hình |
| `incomingCallTimeout` | 2023 | Cuộc gọi đến hết thời gian chờ |
| `incorrectInformation` | 2024 | Thông tin không chính xác |
| `unauthenticated` | 2025 | Chưa xác thực |
| `insufficientBalance` | 2026 | Số dư không đủ |
| `recipientBlocksCalls` | 2027 | Người nhận chặn cuộc gọi |
| `destinationNotFound` | 2028 | Không tìm thấy số đích |
| `callIntervalNotAllowed` | 2029 | Không được phép gọi trong khung giờ này |
| `memberNotActivated` | 2030 | Thành viên chưa kích hoạt |
| `memberNotInProject` | 2031 | Thành viên không thuộc dự án |
| `doNotDisturb` | 2032 | Không làm phiền |
| `destinationGone` | 2033 | Số đích không còn tồn tại |
| `recipientAbsent` | 2034 | Người nhận vắng mặt |
| `packageExpired` | 2035 | Gói cước đã hết hạn |
| `hotlineTelcoNotSupported` | 2036 | Hotline không hỗ trợ nhà mạng |
| `telcoNotFound` | 2037 | Không tìm thấy nhà mạng |
| `invalidParameter` | 2038 | Tham số không hợp lệ |
| `projectExpired` | 2039 | Dự án đã hết hạn |
| `callerCanceled` | 2040 | Người gọi đã hủy |
| `connectionError` | 2041 | Lỗi kết nối |
| `transmissionError` | 2042 | Lỗi đường truyền |
| `unknownError` | 9996 | Lỗi chưa xác định |
| `microphonePermissionDenied` | 9999 | Chưa cấp quyền mic |

**VBotCallEndParty** — bên kết thúc cuộc gọi (trả qua `callEnded(reason:endedBy:)`):

| Value | Mô tả |
|---|---|
| `caller` | Người gọi kết thúc |
| `callee` | Người nhận kết thúc |
| `system` | Hệ thống kết thúc |
| `server` | Server kết thúc |
| `carrier` | Nhà mạng kết thúc |
| `unknown` | Không xác định |

> [!TIP]
> Dùng `callEnded(reason:endedBy:)` delegate để log/tracking chi tiết. Rất hữu ích cho debugging và analytics.
