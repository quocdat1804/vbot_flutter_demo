import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vbot_flutter_demo/call_screen.dart';
import 'package:vbot_flutter_demo/vbot_phone_manager.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final vbotManager = VBotPhoneManager();
  final ScrollController _scrollController = ScrollController();
  String get title => widget.title;
  bool _isCallPagePushed = false;

  @override
  void initState() {
    super.initState();

    vbotManager.init().then(
      (_) {
        vbotManager.callStateStream.listen(
          (sink) {
            if (_isCallPagePushed || !mounted) return;

            // Bỏ qua nếu cuộc gọi đã kết thúc — không mở call screen cho
            // trạng thái disconnected/none (tránh flash UI "cuộc gọi kết thúc")
            if (sink.state == 'disconnected' || sink.state == 'none') return;

            final isIncomingRinging =
                (sink.state == 'incoming' || sink.state == 'confirmed') &&
                    sink.isIncoming;

            final isOutgoingCalling =
                sink.state == 'calling' && !sink.isIncoming;

            if (isIncomingRinging || isOutgoingCalling) {
              // Double-check: cuộc gọi có thể đã kết thúc giữa lúc event
              // emit và thời điểm navigate — bỏ qua nếu đã disconnected
              final latest = vbotManager.currentSink;
              if (latest != null &&
                  (latest.state == 'disconnected' || latest.state == 'none')) {
                return;
              }
              _isCallPagePushed = true;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CallPage()),
              ).then((_) {
                // Khi CallPage pop ra, reset biến lại để có thể push lại nếu cần
                _isCallPagePushed = false;
              });
            }
          },
          onError: (error) => debugPrint("Error in callStateStream: $error"),
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    vbotManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: scaffoldMessengerKey,
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: 32.0,
            ),
            child: Column(
              children: [
                ConnectViewWidget(scrollController: _scrollController),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ConnectViewWidget extends StatefulWidget {
  final ScrollController scrollController;

  const ConnectViewWidget({
    super.key,
    required this.scrollController,
  });

  @override
  State<ConnectViewWidget> createState() => _ConnectViewWidgetState();
}

class _ConnectViewWidgetState extends State<ConnectViewWidget> {
  final vbotManager = VBotPhoneManager();

  // Cấu hình môi trường và Base URL trực tiếp trong code
  static const String configEnvironment = "STAGING";
  static const String configBaseUrl = "";

  final tokenController = TextEditingController();
  final phoneController = TextEditingController();
  final phoneFocusNode = FocusNode();

  VBotHotline? selectedHotline;
  List<VBotHotline> hotlines = [];

  String displayName = "";
  bool isLoading = false;
  bool isConnected = false;
  bool isCalling = false;
  String callee = "";

  @override
  void initState() {
    super.initState();
    phoneFocusNode.addListener(() {
      if (phoneFocusNode.hasFocus) {
        _scrollToField();
      }
    });
    _checkConnect();
  }

  @override
  void dispose() {
    phoneFocusNode.dispose();
    phoneController.dispose();
    tokenController.dispose();
    super.dispose();
  }

  void _scrollToField() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted && phoneFocusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _checkConnect() async {
    bool result = await vbotManager.isUserConnected();
    String? userDisplayName = await vbotManager.userDisplayName();
    if (result) {
      setState(() {
        displayName = userDisplayName ?? "";
        isConnected = true;
      });

      _getHotlines();
    }
  }

  void _connect() async {
    setState(() {
      isLoading = true;
    });

    if (tokenController.text.isEmpty) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      final result = await vbotManager.connect(
        tokenController.text.trim(),
        environment: configEnvironment,
        baseUrl: configBaseUrl,
      );

      if (result != null) {
        setState(() {
          displayName = result;
          isConnected = true;
        });

        _getHotlines();
      } else {
        setState(() {
          displayName = "Error";
          isConnected = false;
        });
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _getHotlines() async {
    var hotlines = await vbotManager.getHotlines();
    if (hotlines != null && hotlines.isNotEmpty) {
      setState(() {
        this.hotlines = hotlines;
        selectedHotline = hotlines[0];
      });
    }
  }

  void _disconnect() async {
    setState(() {
      isLoading = true;
    });

    try {
      await vbotManager.disconnect();
    } finally {
      // The user must be able to retry with another token even when the SDK
      // reports a disconnect error (for example after a lost network session).
      setState(() {
        isConnected = false;
        hotlines = [];
        selectedHotline = null;
        displayName = "";
        isLoading = false;
      });
    }
  }

  void _call() async {
    setState(() {
      isCalling = true;
    });

    final String input = phoneController.text.trim();
    if (input.isEmpty) {
      setState(() {
        isCalling = false;
      });
      return;
    }
    try {
      // Nếu độ dài < 6 ký tự: tự động nhận diện là mã nhánh thành viên (gọi nội bộ, hotline = "")
      // Nếu độ dài >= 6 ký tự: là số điện thoại ngoại mạng (dùng hotline)
      final bool isMemberCall = input.length < 6;

      final String hotlineNumber =
          isMemberCall ? '' : (selectedHotline?.phoneNumber ?? '');

      final calleeName =
          await vbotManager.startCall(input, input, hotlineNumber);
      callee = calleeName ?? "Error";
    } catch (e) {
      print("call exception: $e");
    } finally {
      setState(() {
        isCalling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card 1: Thông tin kết nối & Token
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isConnected ? "Đã kết nối" : "Chưa kết nối",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isConnected ? Colors.green.shade700 : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                if (displayName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 20, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  controller: tokenController,
                  enabled: !isConnected,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.key_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    labelText: 'Token',
                    hintText: 'Nhập Token VBot...',
                  ),
                ),
                const SizedBox(height: 12),
                if (isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (!isConnected)
                  FilledButton.icon(
                    onPressed: _connect,
                    icon: const Icon(Icons.link),
                    label: const Text("Kết nối"),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off, color: Colors.red),
                    label: const Text("Ngắt kết nối", style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Card 2: Chọn Hotline & Gọi điện (khi đã kết nối)
        if (isConnected) ...[
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.phone_in_talk, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Thực hiện cuộc gọi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Hotline Dropdown Form Field
                  DropdownButtonFormField<VBotHotline>(
                    initialValue: selectedHotline,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.headset_mic_outlined),
                      labelText: 'Chọn Hotline',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (VBotHotline? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedHotline = newValue;
                        });
                      }
                    },
                    items: hotlines.map<DropdownMenuItem<VBotHotline>>((VBotHotline value) {
                      final labelText = (value.name.isNotEmpty && value.name != value.phoneNumber)
                          ? "${value.name} - ${value.phoneNumber}"
                          : value.name.isNotEmpty ? value.name : value.phoneNumber;
                      return DropdownMenuItem<VBotHotline>(
                        value: value,
                        child: Text(
                          labelText,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Phone Number / Extension Input
                  TextField(
                    focusNode: phoneFocusNode,
                    controller: phoneController,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+*#]')),
                    ],
                    onTap: _scrollToField,
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        (phoneController.text.trim().isNotEmpty &&
                                phoneController.text.trim().length < 6)
                            ? Icons.badge_outlined
                            : Icons.dialpad,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelText: (phoneController.text.trim().isNotEmpty &&
                              phoneController.text.trim().length < 6)
                          ? 'Mã nhánh thành viên'
                          : 'Số điện thoại / Mã nhánh',
                      hintText: 'Nhập số điện thoại hoặc mã nhánh (ví dụ: 101)...',
                      helperText: (phoneController.text.trim().isNotEmpty &&
                              phoneController.text.trim().length < 6)
                          ? 'Tự động gọi nội bộ (không qua Hotline)'
                          : null,
                      suffixIcon: phoneController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  phoneController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  // Call Button
                  FilledButton.icon(
                    onPressed: isCalling ? null : _call,
                    icon: const Icon(Icons.call),
                    label: Text(
                      isCalling
                          ? "Đang gọi..."
                          : ((phoneController.text.trim().isNotEmpty &&
                                  phoneController.text.trim().length < 6)
                              ? "Gọi thành viên"
                              : "Gọi điện"),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
