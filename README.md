# VBot Flutter SDK Demo

Dự án ví dụ tích hợp VBot Phone SDK cho cả iOS và Android trên nền tảng Flutter.

## 1. Cài đặt SDK vào Flutter Project

### iOS

> **Lưu ý:** SDK yêu cầu iOS 12.0 trở lên và chỉ hoạt động trên thiết bị thật, không dùng iOS Simulator.

Mở tệp `Podfile` trong thư mục `ios` và thực hiện các thay đổi sau:

1. Thêm Pod từ Git repository theo tag phát hành:
```ruby
pod 'VBotPhoneSDKiOS-Public', :git => 'https://github.com/VBotDevTeam/VBotPhoneSDKiOS-Public.git', :tag => '1.1.9'
```

2. Thêm cấu hình build settings bắt buộc trong khối `post_install`:
```ruby
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

Tệp `Podfile` mẫu hoàn chỉnh sẽ tương tự như sau:
```ruby
platform :ios, '13.5'
source "https://cdn.cocoapods.org/"

target 'Runner' do
  use_frameworks!

  pod 'VBotPhoneSDKiOS-Public', :git => 'https://github.com/VBotDevTeam/VBotPhoneSDKiOS-Public.git', :tag => '1.1.9'

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

Sau khi thay đổi Podfile, bạn chạy lệnh sau tại thư mục `ios`:
```bash
pod install
```

3. Trong Xcode, bật **Push Notifications** và **Background Modes**: Audio, AirPlay, and Picture in Picture; Voice over IP; Background Fetch; Remote Notifications. Đồng thời thêm quyền microphone vào `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is necessary to be able to make calls.</string>
```

4. Đăng ký `PKPushRegistry` trong `AppDelegate` và chuyển VoIP payload cho SDK:
```swift
func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
) {
    guard type == .voIP else {
        completion()
        return
    }

    VBotPhone.sharedInstance.startIncomingCall(
        payload: payload,
        completion: completion
    )
}
```

SDK v1.1.9 báo kết thúc cuộc gọi qua callback `callEnded(reason:endedBy:)`; dùng `reason` và `endedBy` cho nghiệp vụ hoặc analytics.

---

### Android

1. Thêm VBot Maven repository vào tệp `settings.gradle` hoặc `build.gradle` ở thư mục gốc của dự án:
```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://raw.githubusercontent.com/VBotDevTeam/VBotPhoneSDKAndroid-Public/main/' }
    }
}
```

2. Thêm SDK vào `android/app/build.gradle`:
```groovy
dependencies {
    implementation 'com.github.VBotDevTeam:VBotPhoneSDKAndroid-Public:1.1.2'
}
```

SDK v1.1.2 đã đóng gói các thư viện mạng bên trong AAR. Không khai báo thủ công RxJava, Gson, Retrofit, OkHttp hoặc Timber.

3. Để nhận cuộc gọi đến, thêm Firebase Messaging và dùng `FirebaseMessagingService` hiện có để chuyển payload chứa `transId` vào `client.notificationCall(...)`. Dự án mẫu đã có sẵn phần tích hợp này trong [FirebaseService.kt](android/app/src/main/kotlin/com/vpmedia/vbotsdksample/FirebaseService.kt).

> **Lưu ý:** Vui lòng thay thế tệp [android/app/google-services.json](android/app/google-services.json) bằng tệp cấu hình Firebase thực tế từ dự án của bạn.

---

## 2. Hướng dẫn sử dụng

Dự án mẫu này sử dụng các kênh Flutter MethodChannel và EventChannel để giao tiếp trực tiếp với native SDK (Kotlin trên Android, Swift trên iOS).

Vui lòng tham khảo mã nguồn chi tiết tại:
- **Flutter Manager:** [lib/vbot_phone_manager.dart](lib/vbot_phone_manager.dart)
- **Native Android Runner:** [android/app/src/main/kotlin/com/vpmedia/vbotsdksample/MainActivity.kt](android/app/src/main/kotlin/com/vpmedia/vbotsdksample/MainActivity.kt)
- **Native iOS Runner:** [ios/Runner/AppDelegate.swift](ios/Runner/AppDelegate.swift)
