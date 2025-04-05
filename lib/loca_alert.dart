import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/main.dart';
import 'package:loca_alert/models/alarm.dart';
import 'package:loca_alert/views/triggered_alarm_dialog.dart';
import 'package:location/location.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';

class LocaAlert extends JuneState {
  List<Alarm> alarms = <Alarm>[];
  Location location = Location();
  
  LocaAlertView view = LocaAlertView.alarms;
  late PageController pageController;

  // Alarms
  Alarm editAlarm = Alarm(name: '', position: const LatLng(0, 0), radius: 100);
  TextEditingController nameInput = TextEditingController();
  Color colorInput = AvailableAlarmColors.blue.value;

  // Map
  MapController mapController = MapController();
  bool mapControllerIsAttached = false; // This let's us know if we can use the controller.
  CacheStore? mapTileCacheStore;
  bool isPlacingAlarm = false;
  double alarmPlacementRadius = 100;
  bool followUserLocation = false;

  // Settings
  late PackageInfo packageInfo;
  bool vibrationSetting = true;
  bool showClosestNonVisibleAlarmSetting = true;

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
    mapTileCacheStore?.close();
    super.onClose();
  }
}

bool deleteAlarmById(LocaAlert locaAlert, String id) {
  for (var i = 0; i < locaAlert.alarms.length; i++) {
    if (locaAlert.alarms[i].id == id) {
      locaAlert.alarms.removeAt(i);
      locaAlert.setState();
      saveAlarms(locaAlert);
      return true;
    }
  }

  return false;
}

Alarm? getAlarmById(LocaAlert locaAlert, String id) {
  for (var alarm in locaAlert.alarms) {
    if (alarm.id == id) return alarm;
  }

  return null;
}

void updateAndSaveAlarm(
  LocaAlert locaAlert,
  Alarm alarm, {
  String? newName,
  LatLng? newPosition,
  double? newRadius,
  Color? newColor,
  bool? isActive,
}) {
  if (newName != null) alarm.name = newName;
  if (newPosition != null) alarm.position = newPosition;
  if (newRadius != null) alarm.radius = newRadius;
  if (newColor != null) alarm.color = newColor;
  if (isActive != null) alarm.active = isActive;

  locaAlert.setState();
  saveAlarms(locaAlert);
}

void addAlarm(LocaAlert locaAlert, Alarm alarm) {
  locaAlert.alarms.add(alarm);
  locaAlert.setState();
  saveAlarms(locaAlert);
}

// This should be called everytime the alarms state is changed.
Future<void> saveAlarms(LocaAlert locaAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
  var file = File(alarmsPath);

  var alarmJsons = List<String>.empty(growable: true);
  for (var alarm in locaAlert.alarms) {
    var alarmMap = alarmToMap(alarm);
    var alarmJson = jsonEncode(alarmMap);
    alarmJsons.add(alarmJson);
  }

  var json = jsonEncode(alarmJsons);
  await file.writeAsString(json);
  debugPrintInfo('Saved alarms to storage: $alarmJsons.');
}

Future<void> loadAlarms(LocaAlert locaAlert) async {
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
    locaAlert.alarms.add(alarm);
  }

  locaAlert.setState();
  debugPrintInfo('Loaded alarms from storage.');
}

Future<void> loadSettings(LocaAlert locaAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var settingsPath = '${directory.path}${Platform.pathSeparator}$settingsFilename';
  var settingsFile = File(settingsPath);

  if (!settingsFile.existsSync()) {
    debugPrintWarning('No settings file found in storage.');
    return;
  }

  var settingsJson = await settingsFile.readAsString();
  if (settingsJson.isEmpty) {
    debugPrintError('No settings found in storage.');
    return;
  }

  var settingsMap = jsonDecode(settingsJson) as Map<String, dynamic>;
  locaAlert.vibrationSetting = settingsMap[settingsAlarmVibrationKey] as bool;
  locaAlert.showClosestNonVisibleAlarmSetting = settingsMap[settingsShowClosestNonVisibleAlarmKey] as bool;
  debugPrintInfo('Loaded settings from storage.');
}

Future<void> saveSettings(LocaAlert locaAlert) async {
  var directory = await getApplicationDocumentsDirectory();
  var settingsPath = '${directory.path}${Platform.pathSeparator}$settingsFilename';
  var settingsFile = File(settingsPath);

  var settingsMap = <String, dynamic>{
    settingsAlarmVibrationKey: locaAlert.vibrationSetting,
    settingsShowClosestNonVisibleAlarmKey: locaAlert.showClosestNonVisibleAlarmSetting,
  };

  var settingsJson = jsonEncode(settingsMap);
  await settingsFile.writeAsString(settingsJson);

  debugPrintInfo('Saved settings to storage.');
}

Future<void> checkAlarms(LocaAlert locaAlert) async {
  var activeAlarms = locaAlert.alarms.where((alarm) => alarm.active).toList();

  var permission = await locaAlert.location.hasPermission();
  if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
    debugPrintError('Alarm Check: Location permission denied. Cannot check for triggered alarms.');
    return;
  }

  var locationData = await locaAlert.location.getLocation();
  if (locationData.latitude == null || locationData.longitude == null) {
    debugPrintWarning('Alarm Check: Cannot determine the user location.');
    return;
  }

  var location = LatLng(locationData.latitude!, locationData.longitude!);
  var triggeredAlarms = detectTriggeredAlarms(location, activeAlarms);
  if (triggeredAlarms.isEmpty) {
    debugPrintInfo('Alarm Check: No alarms triggered.');
    return;
  }

  for (var alarm in triggeredAlarms) {
    debugPrintInfo('Alarm Check: Triggered alarm ${alarm.name} at timestamp ${DateTime.now()}.');

    // Deactivate the alarm so it doesn't trigger again upon next call to checkAlarms.
    updateAndSaveAlarm(locaAlert, alarm, isActive: false);

    var notificationDetails = const NotificationDetails(
      iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentBanner: true, presentSound: true),
    );
    await flutterLocalNotificationsPlugin.show(notificationId++, 'Alarm Triggered', 'You have entered the radius of alarm: ${alarm.name}.', notificationDetails);

    showAlarmDialog(navigatorKey.currentContext!, alarm);
  }

  if (locaAlert.vibrationSetting) {
    debugPrintInfo('Vibrating.');
    for (var i = 0; i < numberOfTriggeredAlarmVibrations; i++) {
      await Vibration.vibrate(duration: 1000);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
    }
  }
}

List<Alarm> detectTriggeredAlarms(LatLng position, List<Alarm> alarms) {
  var triggeredAlarms = <Alarm>[];

  for (var alarm in alarms) {
    var distance = const Distance().as(LengthUnit.Meter, alarm.position, position);
    if (distance <= alarm.radius) triggeredAlarms.add(alarm);
  }

  return triggeredAlarms;
}

T? getClosest<T>(LatLng target, List<T> items, LatLng Function(T) getPosition) {
  T? closestItem;
  var closestDistance = double.infinity;

  for (var item in items) {
    var itemPositon = getPosition(item);
    var d = const Distance().as(LengthUnit.Meter, itemPositon, target);
    if (d < closestDistance) {
      closestDistance = d;
      closestItem = item;
    }
  }

  return closestItem;
}
