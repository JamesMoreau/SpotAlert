import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/main.dart';
import 'package:vibration/vibration.dart';

// Each geofence callback is run in it's own isolate, separated from the main flutter isolate.
// This means it does not have access to the main memory and application state, that is, SpotAlert,
// the widget tree, nor other instances of the callback.

const geofenceEventPortName = 'geofence_event_port';
const triggerTimesFilename = 'geofence_trigger_times';
const deduplicationInterval = Duration(seconds: 10);

class TriggeredAlarmEvent {
  final String id;
  final DateTime timestamp;

  TriggeredAlarmEvent({required this.id, required this.timestamp});

  Map<String, dynamic> toMap() => {'id': id, 'timestamp': timestamp.millisecondsSinceEpoch};

  factory TriggeredAlarmEvent.fromMap(Map<String, dynamic> map) =>
      TriggeredAlarmEvent(id: map['id'] as String, timestamp: .fromMillisecondsSinceEpoch(map['timestamp'] as int));
}

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrintInfo('GeofenceCallbackParams: $params');
  if (params.event != .enter) {
    debugPrintError('Geofence callback received an event other than enter, which should not be possible.');
    return;
  }

  final id = params.geofences.first.id;
  final now = DateTime.now();

  // Sometimes the same geofence can trigger twice for the same event type.
  // Therefore, we must de-duplicate the alarms by checking the last trigger time.
  // Since we cannot persist memory accross callbacks, we need to use the file system instead.
  final directory = await getApplicationDocumentsDirectory();
  final filepath = path.join(directory.path, triggerTimesFilename);
  final file = File(filepath);

  var triggerMap = <String, dynamic>{};

  if (file.existsSync()) {
    try {
      final contents = await file.readAsString();
      triggerMap = jsonDecode(contents) as Map<String, dynamic>;
    } on Exception catch (_) {
      triggerMap = {};
    }
  }

  final lastTimestampMillis = triggerMap[id] as int?;
  if (lastTimestampMillis != null) {
    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastTimestampMillis);

    if (now.difference(lastTime) < deduplicationInterval) {
      debugPrintInfo('Duplicate trigger ignored for $id');
      return;
    }
  }

  triggerMap[id] = now.millisecondsSinceEpoch;
  await file.writeAsString(jsonEncode(triggerMap));

  // Display a notification to the user.
  const title = 'Alarm Triggered';
  const message = 'You have entered the radius of an alarm.';
  const notificationDetails = NotificationDetails(iOS: .new(interruptionLevel: .active));
  try {
    await FlutterLocalNotificationsPlugin().show(id.hashCode, title, message, notificationDetails);
  } on Exception catch (_) {
    debugPrintError('Failed to send notification.');
  }

  // Notify flutter app to display to display the triggered alarm in the ui.
  final port = IsolateNameServer.lookupPortByName(geofenceEventPortName);
  if (port == null) {
    debugPrintError('Unable to resolve callback port.');
    return;
  } else {
    final event = TriggeredAlarmEvent(id: id, timestamp: now);
    port.send(event.toMap());
  }

  // Grab to user's attention. Vibrate last because we need to await it.
  final canVibrate = await Vibration.hasVibrator();
  if (canVibrate) {
    const pause = Duration(seconds: 3);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(pause);
      await Vibration.vibrate();
    }
  }

  await Future<void>.delayed(const Duration(seconds: 1));
}
