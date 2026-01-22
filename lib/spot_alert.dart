import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';

class SpotAlert extends JuneState {
  List<Alarm> alarms = [];
  List<String> activeGeofences = [];
  LatLng? position; // The user's position.

  SpotAlertView view = .alarms;
  late PageController pageController;

  // Alarms
  Alarm editAlarm = Alarm(name: '', position: const LatLng(0, 0), radius: 100);
  TextEditingController nameInput = .new();
  Color colorInput = AvailableAlarmColors.blue.value;

  // Map
  MapController mapController = .new();
  bool mapControllerIsAttached = false; // This let's us know if we can use the controller.
  FMTCTileProvider? tileProvider;
  bool isPlacingAlarm = false;
  double alarmPlacementRadius = initialAlarmPlacementRadius;
  bool followUserLocation = false;

  // Settings
  late PackageInfo packageInfo;

  @override
  Future<void> onInit() async {
    pageController = PageController(initialPage: view.index);
    packageInfo = await PackageInfo.fromPlatform();
    super.onInit();
  }

  @override
  void onClose() {
    pageController.dispose();
    mapController.dispose();
    tileProvider?.dispose();
    super.onClose();
  }
}

bool deleteAlarmById(SpotAlert spotAlert, String id) {
  for (var i = 0; i < spotAlert.alarms.length; i++) {
    if (spotAlert.alarms[i].id == id) {
      spotAlert.alarms.removeAt(i);
      spotAlert.setState();
      saveAlarms(spotAlert);
      return true;
    }
  }

  return false;
}

Alarm? getAlarmById(SpotAlert spotAlert, String id) {
  for (var alarm in spotAlert.alarms) {
    if (alarm.id == id) return alarm;
  }

  return null;
}

void updateAndSaveAlarm(SpotAlert spotAlert, Alarm alarm, {String? newName, LatLng? newPosition, double? newRadius, Color? newColor}) {
  if (newName != null) alarm.name = newName;
  if (newPosition != null) alarm.position = newPosition;
  if (newRadius != null) alarm.radius = newRadius;
  if (newColor != null) alarm.color = newColor;

  spotAlert.setState();
  saveAlarms(spotAlert);
}

Future<void> addAlarm(SpotAlert spotAlert, Alarm alarm) async {
  spotAlert.alarms.add(alarm);
  spotAlert.setState();
  await saveAlarms(spotAlert);
}

Future<void> activateAlarm(SpotAlert spotAlert, Alarm alarm) async {
  final geofence = buildGeofence(alarm);

  try {
    await NativeGeofenceManager.instance.createGeofence(geofence, geofenceTriggered);

    spotAlert.activeGeofences.add(alarm.id);
    spotAlert.setState();

    debugPrintInfo('Added geofence for alarm: ${alarm.id}');
  } on NativeGeofenceException catch (e) {
    if (e.code == .missingLocationPermission || e.code == .missingBackgroundLocationPermission) {
      debugPrintError('Error creating geofence. Did the user grant us the location permission yet?');
    } else if (e.code == .pluginInternal) {
      debugPrintError(
        'Internal geofence error: '
        'message=${e.message}, '
        'detail=${e.details}, '
        'stackTrace=${e.stacktrace}',
      );
    } else {
      debugPrintError(
        'Error creating geofence (${e.code.name}): '
        'message=${e.message}, '
        'detail=${e.details}, '
        'stackTrace=${e.stacktrace}',
      );
    }
  }
}

Future<void> deactivateAlarm(SpotAlert spotAlert, Alarm alarm) async {
  spotAlert.activeGeofences.remove(alarm.id);
  await NativeGeofenceManager.instance.removeGeofenceById(alarm.id);
  debugPrintInfo('Removed geofence for alarm: ${alarm.id}.');
}

Geofence buildGeofence(Alarm alarm) {
  return Geofence(
    id: alarm.id,
    location: .new(latitude: alarm.position.latitude, longitude: alarm.position.longitude),
    radiusMeters: alarm.radius,
    triggers: {.enter},
    iosSettings: const .new(initialTrigger: true),
    androidSettings: const .new(initialTriggers: {.enter}), // Android settings currently unused.
  );
}

// This should be called everytime the alarms state is changed.
Future<void> saveAlarms(SpotAlert spotAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);

  var alarmJsons = List<String>.empty(growable: true);
  for (var alarm in spotAlert.alarms) {
    var alarmMap = alarmToMap(alarm);
    var alarmJson = jsonEncode(alarmMap);
    alarmJsons.add(alarmJson);
  }

  var json = jsonEncode(alarmJsons);
  await file.writeAsString(json);
  debugPrintInfo('Saved alarms to storage: $alarmJsons.');
}

Future<void> loadAlarms(SpotAlert spotAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);

  if (!file.existsSync()) {
    debugPrintWarning('No alarms file found in storage.');
    return;
  }

  var alarmJsons = await file.readAsString();
  if (alarmJsons.isEmpty) {
    debugPrintWarning('No alarms found in storage.');
    return;
  }

  var alarmJsonsList = jsonDecode(alarmJsons) as List;
  for (var alarmJson in alarmJsonsList) {
    var alarmMap = jsonDecode(alarmJson as String) as Map<String, dynamic>;
    var alarm = alarmFromMap(alarmMap);
    spotAlert.alarms.add(alarm);
  }

  spotAlert.setState();
  debugPrintInfo('Loaded alarms from storage.');
}

List<Alarm> detectTriggeredAlarms(LatLng position, List<Alarm> alarms) {
  var triggeredAlarms = <Alarm>[];

  for (var alarm in alarms) {
    var distance = const Distance().distance(alarm.position, position);
    if (distance <= alarm.radius) triggeredAlarms.add(alarm);
  }

  return triggeredAlarms;
}

T? getClosest<T>(LatLng target, List<T> items, LatLng Function(T) getPosition) {
  T? closestItem;
  var closestDistance = double.infinity;

  for (var item in items) {
    var itemPositon = getPosition(item);
    var d = const Distance().distance(itemPositon, target);
    if (d < closestDistance) {
      closestDistance = d;
      closestItem = item;
    }
  }

  return closestItem;
}

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrint('Geofence triggered with params: $params');
  // debugPrintInfo('Triggered alarm ${alarm.name} at timestamp ${DateTime.now()}.');

  // updateAndSaveAlarm(spotAlert, alarm, isActive: false);

  // Setup and fire the alarm package to bring the user's attention.
  // var alarmSettings = alarm_package.AlarmSettings(
  //   id: alarm.id.hashCode,
  //   dateTime: .now(),
  //   assetAudioPath: 'assets/slow_spring_board_repeated.wav',
  //   volumeSettings: const .fixed(volume: 0.8, volumeEnforced: true),
  //   notificationSettings: .new(title: 'Alarm Triggered', body: 'You have entered the radius of alarm: ${alarm.name}', stopButton: 'Stop'),
  // );
  // await alarm_package.Alarm.set(alarmSettings: alarmSettings);

  // showAlarmDialog(navigatorKey.currentContext!, alarm);
}
