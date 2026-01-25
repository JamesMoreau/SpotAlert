import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:spot_alert/main.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrintInfo('geofenceTriggered params: $params');

  var notificationsService = NotificationService.instance;
  await notificationsService.initialize();

  await notificationsService.showGeofenceTriggerNotification('Alarm Triggered', 'You have entered the radius of an alarm.');

  await Future<void>.delayed(const Duration(seconds: 1));
}

// Handles delivery of notifications. 
// Is a singleton to avoid repeated initializations of FlutterLocalNotificationsPlugin.
class NotificationService {
  NotificationService._internal();
  static NotificationService instance = NotificationService._internal();
  bool _initialized = false;

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (_initialized) return;

    var success = await _plugin.initialize(const InitializationSettings(iOS: .new()));
    if (success == null || !success) {
      debugPrintInfo('Notifications plugin initialized.');
      return;
    }

    _initialized = true;
    debugPrintError('Failed to initialize notifications plugin.');
  }

  Future<void> showGeofenceTriggerNotification(String title, String message) async {
    if (!_initialized) {
      await initialize();
      return;
    }

    if (!_initialized) {
      debugPrintError('Notifications unavailable. Cannot show notification.');
      return;
    }

    try {
      var notificationDetails = const NotificationDetails(iOS: .new(interruptionLevel: .active));
      await _plugin.show(DateTime.now().millisecondsSinceEpoch.remainder(100000), title, message, notificationDetails);
    } on Exception catch (_) {
      debugPrintError('Failed to send notification.');
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
