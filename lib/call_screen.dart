import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vbot_flutter_demo/vbot_phone_manager.dart';
import 'package:vbot_flutter_demo/sink.dart';

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final vbotManager = VBotPhoneManager();
  late final StreamSubscription<VBotSink> _sub;

  @override
  void initState() {
    super.initState();

    _sub = vbotManager.callStateStream.listen(
      (vbotSink) {
        if (mounted) {
          setState(() {});
          if (vbotSink.state == 'disconnected') {
            Navigator.pop(context);
          }
        }
      },
      onError: (error) => print("Error in callStateStream: $error"),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cuộc gọi VBot"),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: CallStateWidget(
            sink: vbotManager.currentSink,
          ),
        ),
      ),
    );
  }
}

class CallStateWidget extends StatefulWidget {
  const CallStateWidget({super.key, this.sink});
  final VBotSink? sink;

  @override
  _CallStateWidgetState createState() => _CallStateWidgetState();
}

class _CallStateWidgetState extends State<CallStateWidget> {
  final vbotManager = VBotPhoneManager();
  Timer? _timer;
  DateTime? _startTime;
  final ValueNotifier<String> _callDuration = ValueNotifier("00:00");
  bool _isSpeakerOn = false;

  void muteMic() async {
    await vbotManager.mute();
    setState(() {});
  }

  void toggleSpeaker() async {
    await vbotManager.speaker();
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
  }

  void hangupCall() async {
    await vbotManager.hangup();
  }

  void answerCall() async {
    await vbotManager.answer();
  }

  void _startCallDuration() {
    _startTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentTime = DateTime.now();
      final difference = currentTime.difference(_startTime!);
      final minutes = (difference.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
      final hours = difference.inHours;
      if (hours > 0) {
        _callDuration.value = "${hours.toString().padLeft(2, '0')}:$minutes:$seconds";
      } else {
        _callDuration.value = "$minutes:$seconds";
      }
    });
  }

  void _stopCallDuration() {
    _timer?.cancel();
    _callDuration.value = "00:00";
  }

  @override
  void initState() {
    super.initState();
    setupTimer(vbotManager.currentSink);
  }

  @override
  void didUpdateWidget(covariant CallStateWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    setupTimer(vbotManager.currentSink);
  }

  void setupTimer(VBotSink? callData) {
    final state = callData?.state;

    if (state == 'confirmed' && _startTime == null) {
      _startCallDuration();
    }

    if (state == 'disconnected') {
      _stopCallDuration();
      _startTime = null;
    }
  }

  String _getStatusText(VBotSink? sink) {
    if (sink == null) return "Chưa có thông tin";
    switch (sink.state) {
      case 'calling':
        return "Đang gọi đi...";
      case 'incoming':
        return "Cuộc gọi đến...";
      case 'connecting':
        return "Đang kết nối...";
      case 'confirmed':
        return "Đang trong cuộc gọi";
      case 'disconnected':
        return "Cuộc gọi kết thúc";
      default:
        return sink.state;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sink = widget.sink;

    if (sink == null) {
      return const Center(
        child: Text(
          'Chưa có trạng thái cuộc gọi.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    final callerName = sink.name.isNotEmpty ? sink.name : "Không xác định";
    final isMuted = sink.isMute;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.account_circle,
          size: 96,
          color: Colors.blueGrey,
        ),
        const SizedBox(height: 16),
        Text(
          callerName,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _getStatusText(sink),
          style: const TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        if (sink.state == 'confirmed')
          ValueListenableBuilder<String>(
            valueListenable: _callDuration,
            builder: (context, value, child) {
              return Text(
                'Thời gian: $value',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              );
            },
          ),
        const SizedBox(height: 36),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (sink.state == 'confirmed') ...[
              isMuted
                  ? FilledButton.icon(
                      onPressed: muteMic,
                      icon: const Icon(Icons.mic_off),
                      label: const Text("Bật mic"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: muteMic,
                      icon: const Icon(Icons.mic),
                      label: const Text("Tắt mic"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
              const SizedBox(width: 16),
              _isSpeakerOn
                  ? FilledButton.icon(
                      onPressed: toggleSpeaker,
                      icon: const Icon(Icons.volume_up),
                      label: const Text("Loa ngoài"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: toggleSpeaker,
                      icon: const Icon(Icons.volume_down),
                      label: const Text("Loa trong"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        if (sink.state == 'incoming') ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: hangupCall,
                icon: const Icon(Icons.call_end),
                label: const Text("Từ chối"),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: answerCall,
                icon: const Icon(Icons.call),
                label: const Text("Trả lời"),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ] else if (sink.state == 'confirmed' || sink.state == 'calling' || sink.state == 'connecting') ...[
          FilledButton.icon(
            onPressed: hangupCall,
            icon: const Icon(Icons.call_end),
            label: const Text("Tắt máy"),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _callDuration.dispose();
    super.dispose();
  }
}
