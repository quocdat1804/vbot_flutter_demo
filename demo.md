```dart
@override
void initState() {
    super.initState();

    // Kiểm tra xem có cuộc gọi nào đang hoạt động không
    const hasActiveCall = CallStateManager().hasActiveCall()
    if (hasActiveCall) {
    // Show màn hình call, nếu show rồi thì không làm gì
    }

    // Lắng nghe sự kiện thay đổi trạng thái cuộc gọi
    CallStateManager().callStateStream.listen(
      (vbotSink) {
        if ((vbotSink.state == 'connecting' && vbotSink.isIncoming) ||
            (vbotSink.state == 'calling' && !vbotSink.isIncoming)) {
          // Show màn hình call, nếu show rồi thì không làm gì
        }
      },
      onError: (error) => print("Error in callStateStream: $error"),
    );
}



@override
  void initState() {
    super.initState();

    // Lấy trạng thái cuộc gọi hiện tại
    const callState = CallStateManager().getCallState()
    // Tùy vào trang thái cuộc gọi, thực hiện hành động, update UI tương ứng

    // Có thể dùng StreamBuilder
    // Hoặc CallStateManager().callStateStream.listen()
    // để lắng nghe sự kiện thay đổi trạng thái cuộc gọi
    CallStateManager().callStateStream.listen(
      (vbotSink) {
        const callState = vbotSink.state
        // Tùy vào trang thái cuộc gọi, thực hiện hành động, update UI tương ứng
      },
      onError: (error) => print("Error in callStateStream: $error"),
    );
}


```
