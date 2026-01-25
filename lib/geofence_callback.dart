import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:spot_alert/main.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrintInfo('geofenceTriggered params: $params');

  var id = params.geofences.first.id;

  var success = await FlutterLocalNotificationsPlugin().initialize(const InitializationSettings(iOS: .new()));
  var didInitialize = success ?? false;
  if (!didInitialize) {
    debugPrintError('Notifications unavailable (permission denied or init failed).');
  }

  var title = 'Alarm Triggered';
  var message = 'You have entered the radius of an alarm.';
  var notificationDetails = const NotificationDetails(iOS: .new(interruptionLevel: .active));

  try {
    await FlutterLocalNotificationsPlugin().show(id.hashCode, title, message, notificationDetails);
  } on Exception catch (_) {
    debugPrintError('Failed to send notification.');
  }

  await Future<void>.delayed(const Duration(seconds: 1));
}

  // final SendPort? send =
  //     IsolateNameServer.lookupPortByName('native_geofence_send_port');
  // send?.send(params.event.name);

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
