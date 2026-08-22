class VBotSink {
  final String name;
  final String state;
  final bool isIncoming;
  final bool isMute;
  final bool onHold;

  VBotSink({
    required this.name,
    required this.state,
    required this.isIncoming,
    required this.isMute,
    required this.onHold,
  });

  factory VBotSink.fromMap(Map<String, dynamic> map) {
    return VBotSink(
      name: map['name'] as String? ?? '',
      state: map['state'] as String? ?? '',
      isIncoming: map['isIncoming'] as bool? ?? false,
      isMute: map['isMute'] as bool? ?? false,
      onHold: map['onHold'] as bool? ?? false,
    );
  }

  @override
  String toString() {
    return 'VBotSink(name: $name, state: $state, isIncoming: $isIncoming, isMute: $isMute, onHold: $onHold)';
  }
}
