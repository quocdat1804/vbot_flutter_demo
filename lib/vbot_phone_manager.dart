import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:vbot_flutter_demo/home_page.dart';
import 'sink.dart';

class VBotPhoneManager {
  static final VBotPhoneManager _instance = VBotPhoneManager._internal();
  factory VBotPhoneManager() => _instance;
  VBotPhoneManager._internal();

  static const MethodChannel _methodChannel =
      MethodChannel('com.vpmedia.vbot-sdk/vbot_phone');
  static const EventChannel _eventChannel =
      EventChannel('com.vpmedia.vbot-sdk/call');

  final StreamController<VBotSink> _callStateController =
      StreamController<VBotSink>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;

  VBotSink? currentSink;

  Stream<VBotSink> get callStateStream => _callStateController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (e) => debugPrint("Stream error: $e"),
        onDone: () => debugPrint("Stream closed"));
    _initialized = true;
  }

  void _handleEvent(dynamic event) {
    try {
      final Map<String, dynamic> map = Map<String, dynamic>.from(event as Map);
      final sink = VBotSink.fromMap(map);
      currentSink = sink;
      _callStateController.add(sink);
    } catch (e, st) {
      debugPrint("Error parsing event: $e");
      debugPrint("Stack trace: $st");
    }
  }

  Future<bool> isUserConnected() async {
    try {
      final result = await _methodChannel.invokeMethod('isUserConnected');
      return (result as Map)['isUserConnected'] as bool;
    } catch (e) {
      _showError(e);
      return false;
    }
  }

  Future<String?> userDisplayName() async {
    try {
      final result = await _methodChannel.invokeMethod('userDisplayName');
      return (result as Map)['userDisplayName'] as String?;
    } catch (e) {
      _showError(e);
      return null;
    }
  }

  Future<String?> connect(String token,
      {String? environment, String? baseUrl}) async {
    try {
      final result = await _methodChannel.invokeMethod('connect', {
        'token': token,
        if (environment != null && environment.isNotEmpty)
          'environment': environment,
        if (baseUrl != null && baseUrl.isNotEmpty) 'baseUrl': baseUrl,
      });
      return (result as Map)['displayName'] as String?;
    } catch (e) {
      _showError(e);
      return null;
    }
  }

  Future<bool> disconnect() async {
    try {
      final result = await _methodChannel.invokeMethod('disconnect');
      return (result as Map)['disconnect'] as bool;
    } catch (e) {
      _showError(e);
      return false;
    }
  }

  Future<String?> startCall(
      String name, String phoneNumber, String hotline) async {
    try {
      final result = await _methodChannel.invokeMethod('startCall', {
        'name': name,
        'phoneNumber': phoneNumber,
        'hotline': hotline,
      });
      return (result as Map)['phoneNumber'] as String?;
    } catch (e) {
      _showError(e);
      return null;
    }
  }

  Future<List<VBotHotline>?> getHotlines() async {
    try {
      final result = await _methodChannel.invokeMethod('getHotlines');
      final list = result as List;
      return list
          .map((e) => VBotHotline.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      _showError(e);
      return null;
    }
  }

  Future<void> answer() async {
    try {
      await _methodChannel.invokeMethod('answer');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> hangup() async {
    try {
      await _methodChannel.invokeMethod('hangup');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> mute() async {
    try {
      await _methodChannel.invokeMethod('mute');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> speaker() async {
    try {
      await _methodChannel.invokeMethod('speaker');
    } catch (e) {
      _showError(e);
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _callStateController.close();
  }

  void _showError(Object e) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('An error occurred: $e')),
    );
  }
}

class VBotHotline {
  final String name;
  final String phoneNumber;
  VBotHotline({required this.name, required this.phoneNumber});
  factory VBotHotline.fromMap(Map<String, dynamic> map) => VBotHotline(
        name: map['name'] as String,
        phoneNumber: map['phoneNumber'] as String,
      );
}
