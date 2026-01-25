import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:spot_alert/main.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrintInfo('geofenceTriggered params: $params');

  final notificationsRepository = NotificationsRepository();
  await notificationsRepository.init();

  var title = 'Alarm Triggered';
  await notificationsRepository.showGeofenceTriggerNotification(title, '');

  await Future<void>.delayed(const Duration(seconds: 1));
}

class NotificationsRepository {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return; // prevent re-initialization

    var initSettingsAndroid = const AndroidInitializationSettings('@mipmap/ic_launcher');
    var initSettingsIOs = const DarwinInitializationSettings(defaultPresentBanner: false);

    try {
      final success = await _plugin.initialize( InitializationSettings(android: initSettingsAndroid, iOS: initSettingsIOs));
      if (success == true) {
        _isInitialized = true;
        debugPrintInfo('Notifications plugin initialized.');
        return;
      }
      debugPrintInfo('Failed to initialize notifications plugin.');
    } catch (e) {
      debugPrintInfo('Error while initializing notifications plugin: $e');
    }
  }

  Future<void> showGeofenceTriggerNotification(String title, String message) async {
    if (!_isInitialized) {
      debugPrintInfo('Notifications plugin is not initialized.');
      return;
    }

    try {
      await _plugin.show(
        Random().nextInt(100000),
        title,
        message,
        NotificationDetails(
          android: .new('geofence_triggers', 'Geofence Triggers', styleInformation: BigTextStyleInformation(message)),
          iOS: const .new(interruptionLevel: InterruptionLevel.active),
        ),
        payload: 'item x',
      );
      debugPrintInfo('Notification sent.');
    } catch (e) {
      debugPrintInfo('Failed to send notification: $e');
    }
  }
}

  // final SendPort? send =
  //     IsolateNameServer.lookupPortByName('native_geofence_send_port');
  // send?.send(params.event.name);

  // var id = params.geofences.first.id;
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
