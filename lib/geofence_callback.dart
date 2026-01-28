import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:spot_alert/main.dart';
import 'package:vibration/vibration.dart';

const geofenceCallbackPortName = 'geofence_event_port';

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
  var id = params.geofences.first.id;

  var port = IsolateNameServer.lookupPortByName(geofenceCallbackPortName);
  if (port == null) {
    debugPrintError('Unable to resolve callback port.');
    return;
  }

  var event = TriggeredAlarmEvent(id: id, timestamp: DateTime.now());
  port.send(event.toMap());
  // port.send(id);

  var success = await FlutterLocalNotificationsPlugin().initialize(const InitializationSettings(iOS: .new()));
  var didInitialize = success ?? false;
  if (!didInitialize) {
    debugPrintError('Notifications unavailable (permission denied or initialization failed).');
  }

  var title = 'Alarm Triggered';
  var message = 'You have entered the radius of an alarm.';
  var notificationDetails = const NotificationDetails(iOS: .new(interruptionLevel: .active));

  try {
    await FlutterLocalNotificationsPlugin().show(id.hashCode, title, message, notificationDetails);
  } on Exception catch (_) {
    debugPrintError('Failed to send notification.');
  }

  if (await Vibration.hasVibrator()) {
    await Vibration.vibrate(preset: .rhythmicBuzz);
  }

  await Future<void>.delayed(const Duration(seconds: 1));
}

  // 
  // debugPrint('Alarm with id $id triggered.');

  // WidgetsFlutterBinding.ensureInitialized();
  // await alarm_package.Alarm.init();

  // Setup and fire the alarm package to bring the user's attention.
  // var alarmSettings = alarm_package.AlarmSettings(
  //   id: params.geofences.first.hashCode,
  //   dateTime: .now(),
  //   assetAudioPath: 'assets/slow_spring_board_repeated.wav',
  //   volumeSettings: const .fixed(volume: 0.8, volumeEnforced: true),
  //   notificationSettings: const .new(title: 'Alarm Triggered', body: 'You have entered the radius of an alarm', stopButton: 'Stop'),
  // );
  // await alarm_package.Alarm.set(alarmSettings: alarmSettings);
