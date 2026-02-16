class TriggeredAlarmEvent {
  final String id;
  final DateTime timestamp;

  TriggeredAlarmEvent({required this.id, required this.timestamp});

  Map<String, dynamic> toMap() => {'id': id, 'timestamp': timestamp.millisecondsSinceEpoch};

  factory TriggeredAlarmEvent.fromMap(Map<String, dynamic> map) =>
      TriggeredAlarmEvent(id: map['id'] as String, timestamp: .fromMillisecondsSinceEpoch(map['timestamp'] as int));
}
