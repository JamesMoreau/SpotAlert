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
import 'package:spot_alert/geofence_callback.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';

class SpotAlert extends JuneState {
  List<Alarm> alarms = [];
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
  double alarmPlacementRadius = minimumAlarmRadius;
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

// TODO: make async and use removeWhere.
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

Future<void> updateAndSaveAlarm(SpotAlert spotAlert, Alarm alarm, {String? newName, LatLng? newPosition, double? newRadius, Color? newColor}) async {
  if (newName != null) alarm.name = newName;
  if (newPosition != null) alarm.position = newPosition;
  if (newRadius != null) alarm.radius = newRadius;
  if (newColor != null) alarm.color = newColor;

  spotAlert.setState();
  await saveAlarms(spotAlert);
}

// TODO: make async
Future<void> addAlarm(SpotAlert spotAlert, Alarm alarm) async {
  spotAlert.alarms.add(alarm);
  spotAlert.setState();
  await saveAlarms(spotAlert);
}

enum ActivateAlarmResult { success, limitReached, failed }

Future<ActivateAlarmResult> activateAlarm(SpotAlert spotAlert, Alarm alarm) async {
  var maxGeofenceCountReached = spotAlert.alarms.where((a) => a.active).length >= maxGeofenceCount;
  if (maxGeofenceCountReached) {
    return .limitReached;
  }

  var geofence = Geofence(
    id: alarm.id,
    location: .new(latitude: alarm.position.latitude, longitude: alarm.position.longitude),
    radiusMeters: alarm.radius,
    triggers: {.enter},
    iosSettings: const .new(initialTrigger: true),
    androidSettings: const .new(initialTriggers: {.enter}), // Android settings currently unused.
  );

  try {
    await NativeGeofenceManager.instance.createGeofence(geofence, geofenceTriggered);

    alarm.active = true;
    spotAlert.setState();

    debugPrintInfo('Added geofence for alarm: ${alarm.id}');
    return .success;
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

    return .failed;
  }
}

Future<bool> deactivateAlarm(Alarm alarm) async {
  try {
    await NativeGeofenceManager.instance.removeGeofenceById(alarm.id);
  } on NativeGeofenceException catch (e) {
    debugPrintError(
      'Unable to remove geofence (${e.code.name}): '
      'message=${e.message}, '
      'detail=${e.details}, '
      'stackTrace=${e.stacktrace}',
    );

    return false;
  }

  alarm.active = false;
  debugPrintInfo('Removed geofence for alarm: ${alarm.id}.');

  return true;
}

Future<void> loadGeofences(SpotAlert spotAlert) async {
  List<String> geofenceIds;
  try {
    geofenceIds = await NativeGeofenceManager.instance.getRegisteredGeofenceIds();
  } on NativeGeofenceException catch (e) {
    debugPrintError(
      'Unable to retrieve geofences (${e.code.name}): '
      'message=${e.message}, '
      'detail=${e.details}, '
      'stackTrace=${e.stacktrace}',
    );

    return;
  }

  for (var alarm in spotAlert.alarms) {
    var hasMatchingGeofence = geofenceIds.contains(alarm.id);
    alarm.active = hasMatchingGeofence;
  }

  spotAlert.setState();

  for (var geofenceId in geofenceIds) {
    var isOrphanGeofence = spotAlert.alarms.findById(geofenceId) == null;
    if (isOrphanGeofence) {
      try {
        await NativeGeofenceManager.instance.removeGeofenceById(geofenceId);
        debugPrintWarning('Found and removed orphan geofence $geofenceId');
      } on NativeGeofenceException catch (e) {
        debugPrintError(
          'Unable to remove orphaned geofence (${e.code.name}): '
          'message=${e.message}, '
          'detail=${e.details}, '
          'stackTrace=${e.stacktrace}',
        );
      }
    }
  }
}

// This should be called everytime the alarms state is changed.
Future<void> saveAlarms(SpotAlert spotAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);

  var seenIds = <String>{};
  var alarmJsons = List<String>.empty(growable: true);
  for (var alarm in spotAlert.alarms) {
    var alreadySeen = !seenIds.add(alarm.id);
    if (alreadySeen) {
      debugPrintError('Duplicate alarm id detected while saving: ${alarm.id}. Skipping duplicate.');
      continue;
    }

    var alarmMap = alarmToMap(alarm);
    var alarmJson = jsonEncode(alarmMap);
    alarmJsons.add(alarmJson);
  }

  var json = jsonEncode(alarmJsons);
  await file.writeAsString(json);
  debugPrintInfo('Saved alarms to storage: $alarmJsons.');
}

// TODO: should this take a path instead to avoid global dependency? also move to alarms code.
Future<List<Alarm>> loadAlarmsFromStorage() async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);

  if (!file.existsSync()) {
    debugPrintWarning('No alarms file found in storage.');
    return [];
  }

  var alarmJsons = await file.readAsString();
  if (alarmJsons.isEmpty) {
    debugPrintWarning('No alarms found in storage.');
    return [];
  }

  var decoded = jsonDecode(alarmJsons) as List;
  var seenIds = <String>{};
  var alarms = <Alarm>[];

  for (final alarmJson in decoded) {
    var alarmMap = jsonDecode(alarmJson as String) as Map<String, dynamic>;
    var alarm = alarmFromMap(alarmMap);

    var alreadySeen = !seenIds.add(alarm.id);
    if (alreadySeen) {
      debugPrintError('Duplicate alarm id detected while loading: ${alarm.id}. Skipping duplicate.');
      continue;
    }

    alarms.add(alarm);
  }

  debugPrintInfo('Loaded ${alarms.length} alarms from storage.');
  return alarms;
}
