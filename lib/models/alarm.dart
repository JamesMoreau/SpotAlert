import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/main.dart';

const initialAlarmRadius = 2000.0;
const minimumAlarmRadius = 1000.0;
const maximumAlarmRadius = 10000.0;

class Alarm {
  String id;
  String name;
  Color color;
  LatLng position;
  double radius; // Meters
  bool active; // Corresponds to a geofence being registered with the OS. For this reason it is not serialized.

  Alarm({required this.name, required this.position, required this.radius, String? id, Color? color, this.active = false})
    : assert(radius > 0, 'The radius for an alarm must be greater than zero.'),
      id = id ?? idGenerator.v1(),
      color = color ?? AvailableAlarmColors.redAccent.value;

  void update({String? name, LatLng? position, double? radius, Color? color}) {
    if (name != null) this.name = name;
    if (position != null) this.position = position;
    if (radius != null) this.radius = radius;
    if (color != null) this.color = color;
  }

  factory Alarm.fromMap(Map<String, dynamic> map) {
    final pos = map['position'] as Map<String, dynamic>;
    return Alarm(
      id: map['id'] as String,
      name: map['name'] as String,
      color: Color(map['color'] as int),
      position: LatLng(pos['latitude'] as double, pos['longitude'] as double),
      radius: map['radius'] as double,
      // active defaults to false
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color.toARGB32(),
      'position': {'latitude': position.latitude, 'longitude': position.longitude},
      'radius': radius,
    };
  }
}

enum AvailableAlarmColors {
  blue(Colors.blue),
  green(Colors.green),
  orange(Colors.orange),
  redAccent(Colors.redAccent),
  purple(Colors.purple),
  pink(Colors.pink),
  teal(Colors.teal),
  brown(Colors.brown),
  indigo(Colors.indigo),
  amber(Colors.amber),
  grey(Colors.grey),
  black(Colors.black);

  const AvailableAlarmColors(this.value);
  final Color value;
}

extension AlarmIterable on Iterable<Alarm> {
  Alarm? findById(String id) {
    for (final alarm in this) {
      if (alarm.id == id) return alarm;
    }
    return null;
  }
}

List<Alarm> detectTriggeredAlarms(LatLng position, List<Alarm> alarms) {
  final triggeredAlarms = <Alarm>[];

  for (final alarm in alarms) {
    final distance = const Distance().distance(alarm.position, position);
    if (distance <= alarm.radius) triggeredAlarms.add(alarm);
  }

  return triggeredAlarms;
}

T? getClosest<T>(LatLng target, List<T> items, LatLng Function(T) getPosition) {
  T? closestItem;
  var closestDistance = double.infinity;

  for (final item in items) {
    final itemPositon = getPosition(item);
    final d = const Distance().distance(itemPositon, target);
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

  final contents = await file.readAsString();
  if (contents.isEmpty) {
    debugPrintWarning('No alarms found in file: ${file.path}');
    return [];
  }

  final decoded = jsonDecode(contents) as List;
  final seenIds = <String>{};
  final alarms = <Alarm>[];

  for (final alarmJson in decoded) {
    final alarmMap = jsonDecode(alarmJson as String) as Map<String, dynamic>;
    final alarm = Alarm.fromMap(alarmMap);

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
  final seenIds = <String>{};
  final alarmJsons = <String>[];

  for (final alarm in alarms) {
    if (!seenIds.add(alarm.id)) {
      debugPrintError('Duplicate alarm id detected while saving: ${alarm.id}. Skipping duplicate.');
      continue;
    }

    final alarmMap = alarm.toMap();
    final alarmJson = jsonEncode(alarmMap);
    alarmJsons.add(alarmJson);
  }

  final json = jsonEncode(alarmJsons);
  await file.writeAsString(json);

  debugPrintInfo('Saved ${alarmJsons.length} alarms to ${file.path}.');
}
