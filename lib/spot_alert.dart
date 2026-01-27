import 'dart:async';
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

const maxGeofenceCount = 20; // This limit comes from Apple's API, restricting the number of geofences per application.

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
  double alarmPlacementRadius = initialAlarmRadius;
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

Future<List<String>> getGeofenceIds() async {
  try {
    return await NativeGeofenceManager.instance.getRegisteredGeofenceIds();
  } on NativeGeofenceException catch (e) {
    debugPrintError(
      'Unable to retrieve geofences (${e.code.name}): '
      'message=${e.message}, '
      'detail=${e.details}, '
      'stackTrace=${e.stacktrace}',
    );
    return [];
  }
}

Future<void> reconcileAlarmsAndGeofences(List<Alarm> alarms, List<String> geofenceIds) async {
  // Mark alarms as active if they exist in OS
  for (var alarm in alarms) {
    alarm.active = geofenceIds.contains(alarm.id);
  }

  // Remove orphan geofences (exist in OS but no matching alarm)
  for (var geofenceId in geofenceIds) {
    var isOrphan = alarms.findById(geofenceId) == null;
    if (!isOrphan) continue;

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

// This should be called everytime the alarms state is changed.
Future<void> saveAlarms(SpotAlert spotAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);
  await saveAlarmsToFile(file, spotAlert.alarms);
}
