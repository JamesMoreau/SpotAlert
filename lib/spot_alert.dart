import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alarm/alarm.dart' as alarm_package;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/views/triggered_alarm_dialog.dart';

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
  double alarmPlacementRadius = 100;
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

void updateAndSaveAlarm(SpotAlert spotAlert, Alarm alarm, {String? newName, LatLng? newPosition, double? newRadius, Color? newColor, bool? isActive}) {
  if (newName != null) alarm.name = newName;
  if (newPosition != null) alarm.position = newPosition;
  if (newRadius != null) alarm.radius = newRadius;
  if (newColor != null) alarm.color = newColor;
  if (isActive != null) alarm.active = isActive;

  spotAlert.setState();
  saveAlarms(spotAlert);
}

void addAlarm(SpotAlert spotAlert, Alarm alarm) {
  spotAlert.alarms.add(alarm);
  spotAlert.setState();
  saveAlarms(spotAlert);
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

Future<void> checkAlarms(SpotAlert spotAlert) async {
  if (spotAlert.position == null) {
    debugPrintInfo('Alarm Check: User position not available.');
    return;
  }

  var activeAlarms = spotAlert.alarms.where((alarm) => alarm.active).toList();
  if (activeAlarms.isEmpty) {
    debugPrintInfo('Alarm Check: No active alarms.');
    return;
  }

  var triggeredAlarms = detectTriggeredAlarms(spotAlert.position!, activeAlarms);
  if (triggeredAlarms.isEmpty) {
    debugPrintInfo('Alarm Check: No alarms triggered.');
    return;
  }

  for (var alarm in triggeredAlarms) {
    debugPrintInfo('Alarm Check: Triggered alarm ${alarm.name} at timestamp ${DateTime.now()}.');

    // Deactivate the alarm so it doesn't trigger again upon next call to checkAlarms.
    updateAndSaveAlarm(spotAlert, alarm, isActive: false);

    // Setup and fire the alarm package to bring the user's attention.
    var alarmSettings = alarm_package.AlarmSettings(
      id: alarm.id.hashCode,
      dateTime: .now(),
      assetAudioPath: 'assets/slow_spring_board_repeated.wav',
      volumeSettings: const .fixed(volume: 0.8, volumeEnforced: true),
      notificationSettings: .new(
        title: 'Alarm Triggered',
        body: 'You have entered the radius of alarm: ${alarm.name}',
        stopButton: 'Stop',
      ),
    );
    await alarm_package.Alarm.set(alarmSettings: alarmSettings);

    showAlarmDialog(navigatorKey.currentContext!, alarm);
  }
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
