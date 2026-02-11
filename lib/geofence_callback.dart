import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:spot_alert/main.dart';
import 'package:vibration/vibration.dart';

// The geofence callback is run in it's own isolate, seperated from the main flutter isolate.
// This means it does not have access to the main memory and application state, that is, SpotAlert,
// nor the widget tree.

const geofenceEventPortName = 'geofence_event_port';

class TriggeredAlarmEvent {
  final String id;
  final DateTime timestamp;

  TriggeredAlarmEvent({required this.id, required this.timestamp});

  Map<String, dynamic> toMap() => {'id': id, 'timestamp': timestamp.millisecondsSinceEpoch};

  factory TriggeredAlarmEvent.fromMap(Map<String, dynamic> map) =>
      TriggeredAlarmEvent(id: map['id'] as String, timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int));
}

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  final id = params.geofences.first.id;

  final port = IsolateNameServer.lookupPortByName(geofenceEventPortName);
  if (port == null) {
    debugPrintError('Unable to resolve callback port.');
    return;
  }

  final event = TriggeredAlarmEvent(id: id, timestamp: DateTime.now());
  port.send(event.toMap());

  const title = 'Alarm Triggered';
  const message = 'You have entered the radius of an alarm.';
  const notificationDetails = NotificationDetails(iOS: .new(interruptionLevel: .active));

  try {
    await FlutterLocalNotificationsPlugin().show(id.hashCode, title, message, notificationDetails);
  } on Exception catch (_) {
    debugPrintError('Failed to send notification.');
  }

  if (await Vibration.hasVibrator()) {
    await Vibration.vibrate(pattern: [2000, 1000, 2000, 1000, 2000, 1000, 2000, 1000, 2000, 1000, 2000, 1000]);
  }

  await Future<void>.delayed(const Duration(seconds: 1));
}
