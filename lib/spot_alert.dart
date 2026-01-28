import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/geofence_callback.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/views/map.dart';
import 'package:spot_alert/views/triggered_alarm_dialog.dart';

const mapTileStoreName = 'mapStore';
const alarmsFilename = 'alarms.json';
const geofenceNumberLimit = 20; // This limit comes from Apple's API, restricting the number of geofences per application.

class SpotAlert extends JuneState {
  List<Alarm> alarms = [];
  LatLng? position; // The user's position.
  late ReceivePort geofencePort;

  SpotAlertView view = .alarms;
  late PageController pageController = PageController(initialPage: view.index);

  // Alarms
  Alarm editAlarm = Alarm(name: '', position: const LatLng(0, 0), radius: 100);
  TextEditingController nameInput = .new();
  Color colorInput = AvailableAlarmColors.blue.value;

  // Map
  MapController mapController = .new();
  bool mapControllerIsAttached = false; // This let's us know if we can use the controller.
  late FMTCTileProvider tileProvider;
  bool isPlacingAlarm = false;
  double alarmPlacementRadius = initialAlarmRadius;
  bool followUserLocation = false;

  // Settings
  late PackageInfo packageInfo;

  @override
  Future<void> onInit() async {
    alarms = await loadAlarms();
    await loadGeofencesForAlarms(alarms);

    geofencePort = setupGeofenceEventPort();
    geofencePort.listen((message) => handleGeofenceEvent(message, alarms));

    var locationSettings = const LocationSettings(accuracy: .bestForNavigation);
    var stream = Geolocator.getPositionStream(locationSettings: locationSettings);
    stream.listen((position) => handlePositionUpdate(position, this), onError: (dynamic error) => onPositionStreamError(error, this));

    await const FMTCStore(mapTileStoreName).manage.create();
    tileProvider = FMTCTileProvider(stores: const {mapTileStoreName: .readUpdateCreate});

    packageInfo = await PackageInfo.fromPlatform();

    super.onInit();
  }

  @override
  void onClose() {
    pageController.dispose();
    mapController.dispose();
    tileProvider.dispose();

    IsolateNameServer.removePortNameMapping(geofenceCallbackPortName); // Fixes hot-reloading.
    geofencePort.close();
    super.onClose();
  }
}

Future<List<Alarm>> loadAlarms() async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);
  var alarms = await loadAlarmsFromFile(file);
  return alarms;
}

Future<void> loadGeofencesForAlarms(List<Alarm> alarms) async {
  await NativeGeofenceManager.instance.initialize();
  var geofenceIds = await getGeofenceIds();

  // Mark alarms as active if they exist in OS.
  for (var alarm in alarms) {
    alarm.active = geofenceIds.contains(alarm.id);
  }

  // Reconcile alarms by cleaning up orphan geofences (exist in OS but no matching alarm).
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

ReceivePort setupGeofenceEventPort() {
  var port = ReceivePort();

  // Removing and re-registering the fixes hot-reloading issue.
  IsolateNameServer.removePortNameMapping(geofenceCallbackPortName);
  var success = IsolateNameServer.registerPortWithName(port.sendPort, geofenceCallbackPortName);
  if (!success) {
    port.close();
    throw StateError(
      'Fatal: unable to register geofence callback port '
      '($geofenceCallbackPortName). App cannot function.',
    );
  }

  return port;
}

Future<void> handleGeofenceEvent(dynamic message, List<Alarm> alarms) async {
  var event = TriggeredAlarmEvent.fromMap(message as Map<String, dynamic>);

  var triggered = alarms.findById(event.id);
  if (triggered == null) {
    debugPrintError('Unable to retrieve triggered alarm given by id: ${event.id}');
    return;
  }

  debugPrintInfo('Alarm id ${triggered.id} triggered at ${event.timestamp}');

  var success = await deactivateAlarm(triggered);
  if (!success) {
    debugPrintError('Unable to deactive triggered alarm: ${triggered.id}');
    return;
  }

  showAlarmDialog(navigatorKey.currentContext!, triggered);
}

Future<void> handlePositionUpdate(Position position, SpotAlert spotAlert) async {
  spotAlert.position = LatLng(position.latitude, position.longitude);
  spotAlert.setState();

  if (spotAlert.followUserLocation) moveMapToUserLocation(spotAlert);
}

void onPositionStreamError(dynamic error, SpotAlert spotAlert) {
  debugPrintError('Gelocator position stream error');

  spotAlert.position = null;
  spotAlert.followUserLocation = false;
  spotAlert.setState();
}

enum ActivateAlarmResult { success, limitReached, failed }

Future<ActivateAlarmResult> activateAlarm(Alarm alarm) async {
  var geofenceIds = await getGeofenceIds();

  var geofenceAlreadyExistsForAlarm = geofenceIds.contains(alarm.id);
  if (geofenceAlreadyExistsForAlarm) {
    alarm.active = true;
    return ActivateAlarmResult.success;
  }

  var maxGeofenceLimitReached = geofenceIds.length >= geofenceNumberLimit;
  if (maxGeofenceLimitReached) {
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

// This should be called everytime the alarms state is changed.
Future<void> saveSpotAlertAlarms(SpotAlert spotAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);
  await saveAlarmsToFile(file, spotAlert.alarms);
}
