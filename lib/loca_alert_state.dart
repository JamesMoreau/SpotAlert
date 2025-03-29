import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/constants.dart';
import 'package:loca_alert/main.dart';
import 'package:loca_alert/models/alarm.dart';
import 'package:loca_alert/views/triggered_alarm_dialog.dart';
import 'package:location/location.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:vibration/vibration.dart';

class LocaAlert extends JuneState {
	List<Alarm> alarms = <Alarm>[];

	LatLng? userLocation;

	// EditAlarmDialog Stuff
	Alarm? bufferAlarm;
	TextEditingController nameInputController = TextEditingController();

	ProximityAlarmViews currentView = ProximityAlarmViews.alarms;
	late PageController pageController;
	bool alarmIsCurrentlyTriggered = false;

	// MapView stuff. The booleans such as showMarkersInsteadOfCircles and closestAlarmIsInView are necessary because mapController
  // cannot be accessed within the build method of the map view. So instead we update these booleans using myOnMapEvent.
	MapController mapController = MapController();
  LatLng? initialCenter = const LatLng(0, 0);
	bool isPlacingAlarm = false;
	double alarmPlacementRadius = 100;
	bool showMarkersInsteadOfCircles = false; 
	Alarm? closestAlarm;
	bool closestAlarmIsInView = false;
	CacheStore? mapTileCacheStore;
	bool followUserLocation = false;

	bool vibration = true;
	bool showClosestOffScreenAlarm = true;

  late String appName;
  late String packageName;
  late String version;
  late String buildNumber;

	@override
	Future<void> onInit() async {
		pageController = PageController(initialPage: currentView.index);
    
    var packageInfo = await PackageInfo.fromPlatform();
    appName     = packageInfo.appName;
    packageName = packageInfo.packageName;
    version     = packageInfo.version;
    buildNumber = packageInfo.buildNumber;

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

// This is used to produce unique ids. Only one instantiation is needed.
const Uuid idGenerator = Uuid();

bool deleteAlarmById(String id) {
	var state = June.getState(() => LocaAlert());
	for (var i = 0; i < state.alarms.length; i++) {
		if (state.alarms[i].id == id) {
			state.alarms.removeAt(i);
			state.setState();
			saveAlarmsToStorage();
			return true;
		}
	}

	return false;
}

Alarm? getAlarmById(String id) {
	var state = June.getState(() => LocaAlert());

	for (var alarm in state.alarms) {
		if (alarm.id == id) return alarm;
	}

	return null;
}

// Pass the new alarm data here to update proxalarm state. The id field in newAlarmData is ignored. returns success.
bool updateAlarmById(String id, Alarm newAlarmData) {
	var state = June.getState(() => LocaAlert());

	for (var alarm in state.alarms) {
		if (alarm.id == id) {
			alarm.name     = newAlarmData.name;
			alarm.position = newAlarmData.position;
			alarm.radius   = newAlarmData.radius;
			alarm.color    = newAlarmData.color;
			alarm.active   = newAlarmData.active;
			state.setState();
			saveAlarmsToStorage();
			return true;
		}
	}

	return false;
}

void addAlarm(Alarm alarm) {
	var state = June.getState(() =>LocaAlert());

	state.alarms.add(alarm);
	state.setState();
	saveAlarmsToStorage();
}

// This saves all current alarms to shared preferences. Should be called everytime the alarms state is changed.
Future<void> saveAlarmsToStorage() async {
	var state = June.getState(() => LocaAlert());
	
	var directory = await getApplicationDocumentsDirectory();
	var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
	var file = File(alarmsPath);

	var alarmJsons = List<String>.empty(growable: true);
	for (var alarm in state.alarms) {
		var alarmMap = alarmToMap(alarm);
		var alarmJson = jsonEncode(alarmMap);
		alarmJsons.add(alarmJson);
	}

	var json = jsonEncode(alarmJsons);
	await file.writeAsString(json);
	debugPrintSuccess('Saved alarms to storage: $alarmJsons.');
}

Future<void> loadAlarmsFromStorage() async {
	var state = June.getState(() => LocaAlert());

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
		state.alarms.add(alarm);
	}

	state.setState();
	debugPrintSuccess('Loaded alarms from storage.');
}

Future<void> loadSettingsFromStorage() async {
	var state = June.getState(() => LocaAlert());

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
	state.vibration = settingsMap[settingsAlarmVibrationKey] as bool;
	state.showClosestOffScreenAlarm = settingsMap[settingsShowClosestOffScreenAlarmKey] as bool;
	debugPrintSuccess('Loaded settings from storage.');
}

Future<void> clearAlarmsFromStorage() async {
	var directory = await getApplicationDocumentsDirectory();
	var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
	var alarmsFile = File(alarmsPath);

	if (!alarmsFile.existsSync()) {
		debugPrintWarning('No alarms file found in storage. Cannot clear alarms.');
		return;
	}

	await alarmsFile.delete();
	debugPrintSuccess('Cleared alarms from storage.');
}

void resetAlarmPlacementUIState() {
	var state = June.getState(() => LocaAlert());
	state.isPlacingAlarm = false;
	state.alarmPlacementRadius = 100;
}

void changeVibration({required bool newValue}) {
	var state = June.getState(() => LocaAlert());
	state.vibration = newValue;
	state.setState();
	saveSettingsToStorage();
}

void changeShowClosestOffScreenAlarm({required bool newValue}) {
	var state = June.getState(() => LocaAlert());
	state.showClosestOffScreenAlarm = newValue;
	state.setState();
	saveSettingsToStorage();
}

Future<void> saveSettingsToStorage() async {
	var state = June.getState(() => LocaAlert());
	var directory = await getApplicationDocumentsDirectory();
	var settingsPath = '${directory.path}${Platform.pathSeparator}$settingsFilename';
	var settingsFile = File(settingsPath);

	var settingsMap = <String, dynamic>{
		settingsAlarmVibrationKey:            state.vibration,
		settingsShowClosestOffScreenAlarmKey: state.showClosestOffScreenAlarm,
	};

	var settingsJson = jsonEncode(settingsMap);
	await settingsFile.writeAsString(settingsJson);

	debugPrintSuccess('Saved settings to storage.');
}

Future<void> checkAlarms() async {
  var state = June.getState(() => LocaAlert());
  var activeAlarms = state.alarms.where((alarm) => alarm.active).toList();

  var permission = await location.hasPermission();
  if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
    debugPrintError('Alarm Check: Location permission denied. Cannot check for triggered alarms.');
    return;
  }

  var userPositionReference = state.userLocation;
  if (userPositionReference == null) {
    debugPrintWarning('Alarm Check: No user position found.');
    return;
  }

  var triggeredAlarms = checkIfUserTriggersAlarms(userPositionReference, activeAlarms);
  if (triggeredAlarms.isEmpty) {
    debugPrintInfo('Alarm Check: No alarms triggered.');
    return;
  }

  for (var alarm in triggeredAlarms) debugPrintInfo('Alarm Check: Triggered alarm ${alarm.name} at timestamp ${DateTime.now()}.');

  // If another alarm is already triggered, ignore the new alarm.
  if (state.alarmIsCurrentlyTriggered) return;

  var triggeredAlarm = triggeredAlarms[0]; // For now, we only handle one triggered alarm at a time. Although it is possible to have multiple alarms triggered at the same time.
  triggeredAlarm.active = false; // Deactivate the alarm so it doesn't trigger again upon user location changing.

  debugPrintInfo('Alarm Check: Sending the user a notification for alarm ${triggeredAlarm.name}.');
  var notificationDetails = const NotificationDetails(
    iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentBanner: true, presentSound: true),
  );
  await flutterLocalNotificationsPlugin.show(id++, 'Alarm Triggered', 'You have entered the radius of alarm: ${triggeredAlarm.name}.', notificationDetails);

  // No alarm is currently triggered, so we can show the dialog.
  state.alarmIsCurrentlyTriggered = true;
  showAlarmDialog(NavigationService.navigatorKey.currentContext!, triggeredAlarm.id);

  if (state.vibration) {
    for (var i = 0; i < numberOfTriggeredAlarmVibrations; i++) {
      await Vibration.vibrate(duration: 1000);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
    }
  }
}

List<Alarm> checkIfUserTriggersAlarms(LatLng userPosition, List<Alarm> alarms) {
	var triggeredAlarms = <Alarm>[];

	for (var alarm in alarms) {
    var distance = const Distance().as(LengthUnit.Meter, alarm.position, userPosition);
		if (distance <= alarm.radius) triggeredAlarms.add(alarm);
	}

	return triggeredAlarms;
}

Alarm? getClosestAlarmToPosition(LatLng position, List<Alarm> alarms) {
	Alarm? closestAlarm;
	var closestDistance = double.infinity;

	if (alarms.isEmpty) return null;

	for (var alarm in alarms) {
    var distance = const Distance().as(LengthUnit.Meter, alarm.position, position);
		if (distance < closestDistance) {
			closestAlarm = alarm;
			closestDistance = distance;
		}
	}

	return closestAlarm;
}
