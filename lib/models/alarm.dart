import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/main.dart';

const minimumAlarmRadius = 500.0;
const maximumAlarmRadius = 15000.0;

class Alarm {
  String id;
  String name;
  Color color;
  LatLng position;
  double radius; // Meters
  bool active; // Corresponds to a geofence being registered with the OS. For this reason it is not serialized.

  Alarm({required this.name, required this.position, required this.radius, String? id, Color? color, this.active = false})
    : assert(radius > 0),
      id = id ?? idGenerator.v1(),
      color = color ?? AvailableAlarmColors.redAccent.value;
}

extension AlarmUpdate on Alarm {
  void update({String? name, LatLng? position, double? radius, Color? color}) {
    if (name != null) this.name = name;
    if (position != null) this.position = position;
    if (radius != null) this.radius = radius;
    if (color != null) this.color = color;
  }
}

// TODO: refactor these to be extensions.
Map<String, dynamic> alarmToMap(Alarm alarm) {
  return {
    'id': alarm.id,
    'name': alarm.name,
    'color': alarm.color.toARGB32(),
    'position': {'latitude': alarm.position.latitude, 'longitude': alarm.position.longitude},
    'radius': alarm.radius,
  };
}

Alarm alarmFromMap(Map<String, dynamic> alarmJson) {
  return Alarm(
    id: alarmJson['id'] as String,
    name: alarmJson['name'] as String,
    color: Color(alarmJson['color'] as int),
    position: LatLng((alarmJson['position'] as Map<String, dynamic>)['latitude'] as double, (alarmJson['position'] as Map<String, dynamic>)['longitude'] as double),
    radius: alarmJson['radius'] as double,
    // active defaults to false
  );
}

extension AlarmIterable on Iterable<Alarm> {
  Alarm? findById(String id) {
    for (var alarm in this) {
      if (alarm.id == id) return alarm;
    }
    return null;
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

Future<List<Alarm>> loadAlarmsFromFile(File file) async {
  if (!file.existsSync()) {
    debugPrintWarning('No alarms file found: ${file.path}');
    return [];
  }

  var contents = await file.readAsString();
  if (contents.isEmpty) {
    debugPrintWarning('No alarms found in file: ${file.path}');
    return [];
  }

  var decoded = jsonDecode(contents) as List;
  var seenIds = <String>{};
  var alarms = <Alarm>[];

  for (var alarmJson in decoded) {
    var alarmMap = jsonDecode(alarmJson as String) as Map<String, dynamic>;
    var alarm = alarmFromMap(alarmMap);

    if (!seenIds.add(alarm.id)) {
      debugPrintError('Duplicate alarm id detected while loading: ${alarm.id}. Skipping duplicate.');
      continue;
    }

    alarms.add(alarm);
  }

  debugPrintInfo('Loaded ${alarms.length} alarms from ${file.path}.');
  return alarms;
}

Future<void> saveAlarmsToFile(File file, List<Alarm> alarms) async {
  var seenIds = <String>{};
  var alarmJsons = <String>[];

  for (var alarm in alarms) {
    if (!seenIds.add(alarm.id)) {
      debugPrintError('Duplicate alarm id detected while saving: ${alarm.id}. Skipping duplicate.');
      continue;
    }

    var alarmMap = alarmToMap(alarm);
    var alarmJson = jsonEncode(alarmMap);
    alarmJsons.add(alarmJson);
  }

  var json = jsonEncode(alarmJsons);
  await file.writeAsString(json);

  debugPrintInfo('Saved ${alarmJsons.length} alarms to ${file.path}.');
}
