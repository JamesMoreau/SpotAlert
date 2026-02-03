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
import 'package:spot_alert/views/triggered_alarm_dialog.dart';

const mapTileStoreName = 'mapStore';
const alarmsFilename = 'alarms.json';
const geofenceNumberLimit = 20; // This limit comes from Apple's API, restricting the number of geofences per application.

class SpotAlert extends JuneState {
  final List<Alarm> alarms = [];
  late final Stream<LatLng> positionStream;
  final ReceivePort geofencePort = setupGeofenceEventPort(geofenceEventPortName);
  SpotAlertView view = .alarms;
  late final PageController pageController = .new(initialPage: view.index);

  // Map View
  final MapController mapController = .new();
  final Completer<void> mapIsReady = Completer<void>(); // This let's us know if we can use the controller.
  late final FMTCTileProvider tileProvider;
  bool isPlacingAlarm = false;
  double alarmPlacementRadius = initialAlarmRadius;
  bool followUser = false;

  // Settings View
  late final PackageInfo packageInfo;

  @override
  Future<void> onInit() async {
    super.onInit();

    alarms.addAll(await loadAlarms());
    await loadGeofencesForAlarms(alarms);

    geofencePort.listen((message) => handleGeofenceEvent(message, alarms, globalNavigatorKey.currentState));

    positionStream = initializePositionStream(const .new(accuracy: .bestForNavigation));
    positionStream.listen(
      (p) {
        if (followUser) tryMoveMap(this, p);
      },
      onError: (dynamic error) {
        followUser = false;
        setState();
      },
    );

    tileProvider = await initializeTileProvider(mapTileStoreName);

    packageInfo = await PackageInfo.fromPlatform();

    setState();
  }

  @override
  void onClose() {
    tileProvider.dispose();
    mapController.dispose();
    pageController.dispose();

    IsolateNameServer.removePortNameMapping(geofenceEventPortName); // Fixes hot-reloading.
    geofencePort.close();
    super.onClose();
  }
}

Future<List<Alarm>> loadAlarms() async {
  final directory = await getApplicationDocumentsDirectory();
  final alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  final file = File(alarmsPath);
  final alarms = await loadAlarmsFromFile(file);
  return alarms;
}

Stream<LatLng> initializePositionStream(LocationSettings settings) {
  return Geolocator.getPositionStream(locationSettings: settings).map((p) => LatLng(p.latitude, p.longitude)).asBroadcastStream();
}

Future<FMTCTileProvider> initializeTileProvider(String storeName) async {
  final store = FMTCStore(storeName);
  await store.manage.create();

  return FMTCTileProvider(stores: {storeName: .readUpdateCreate});
}

ReceivePort setupGeofenceEventPort(String portNmae) {
  final port = ReceivePort();

  // Removing and re-registering the fixes hot-reloading issue.
  IsolateNameServer.removePortNameMapping(portNmae);
  final success = IsolateNameServer.registerPortWithName(port.sendPort, portNmae);
  if (!success) {
    port.close();
    throw StateError(
      'Fatal: unable to register geofence callback port '
      '($portNmae). App cannot function.',
    );
  }

  return port;
}

Future<void> handleGeofenceEvent(dynamic message, List<Alarm> alarms, NavigatorState? navigator) async {
  final event = TriggeredAlarmEvent.fromMap(message as Map<String, dynamic>);

  final triggered = alarms.findById(event.id);
  if (triggered == null) {
    debugPrintError('Unable to retrieve triggered alarm given by id: ${event.id}');
    return;
  }

  debugPrintInfo('Alarm id ${triggered.id} triggered at ${event.timestamp}');

  final success = await deactivateAlarm(triggered);
  if (!success) {
    debugPrintError('Unable to deactive triggered alarm: ${triggered.id}');
    return;
  }

  if (navigator == null) {
    debugPrintError('Unable to show alarm dialog: navigator not ready');
    return;
  }

  showAlarmDialog(navigator, triggered);
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

Future<void> loadGeofencesForAlarms(List<Alarm> alarms) async {
  await NativeGeofenceManager.instance.initialize();
  final geofenceIds = await getGeofenceIds();

  // Mark alarms as active if they exist in OS.
  for (final alarm in alarms) {
    alarm.active = geofenceIds.contains(alarm.id);
  }

  // Reconcile alarms by cleaning up orphan geofences (exist in OS but no matching alarm).
  for (final geofenceId in geofenceIds) {
    final isOrphan = alarms.findById(geofenceId) == null;
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

Future<bool> followOrUnfollowUser(SpotAlert spotAlert) async {
  final shouldFollow = !spotAlert.followUser;

  if (shouldFollow) {
    // If we are following, then we need to move the map immediately instead
    // of waiting for the next location update.

    final position = await Geolocator.getLastKnownPosition();
    if (position == null) {
      debugPrintInfo('Cannot follow the user since there is no known position.');
      return false;
    }

    final latlng = LatLng(position.latitude, position.longitude);
    final success = tryMoveMap(spotAlert, latlng);
    if (!success) {
      debugPrintWarning('Could not follow user since the map is not ready.');
      return false;
    }
  }

  // Commit state only after success
  spotAlert.followUser = shouldFollow;
  return true;
}

bool tryMoveMap(SpotAlert spotAlert, LatLng position) {
  if (!spotAlert.mapIsReady.isCompleted) return false;

  final zoom = spotAlert.mapController.camera.zoom;
  final success = spotAlert.mapController.move(position, zoom);

  return success;
}

enum ActivateAlarmResult { success, limitReached, failed }

Future<ActivateAlarmResult> activateAlarm(Alarm alarm) async {
  final geofenceIds = await getGeofenceIds();

  final geofenceAlreadyExistsForAlarm = geofenceIds.contains(alarm.id);
  if (geofenceAlreadyExistsForAlarm) {
    alarm.active = true;
    return ActivateAlarmResult.success;
  }

  final maxGeofenceLimitReached = geofenceIds.length >= geofenceNumberLimit;
  if (maxGeofenceLimitReached) {
    return .limitReached;
  }

  final geofence = Geofence(
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

// This should be called everytime the alarms state is changed.
Future<void> saveAlarmsToStorage(SpotAlert spotAlert) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';

    final file = File(alarmsPath);
    await saveAlarmsToFile(file, spotAlert.alarms);
  } on MissingPlatformDirectoryException catch (e) {
    debugPrintError('Failed to save alarms: $e');
  }
}
