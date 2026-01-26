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
  
  Alarm({
    required this.name,
    required this.position,
    required this.radius,
    String? id,
    Color? color,
    this.active = false,
  })  : assert(radius > 0),
        id = id ?? idGenerator.v1(),
        color = color ?? AvailableAlarmColors.redAccent.value;
}

Map<String, dynamic> alarmToMap(Alarm alarm) {
  return {
    'id': alarm.id,
    'name': alarm.name,
    'color': alarm.color.toARGB32(),
    'position': {
      'latitude': alarm.position.latitude,
      'longitude': alarm.position.longitude,
    },
    'radius': alarm.radius,
  };
}

Alarm alarmFromMap(Map<String, dynamic> alarmJson) {
  return Alarm(
    id: alarmJson['id'] as String,
    name: alarmJson['name'] as String,
    color: Color(alarmJson['color'] as int),
    position: LatLng(
      (alarmJson['position'] as Map<String, dynamic>)['latitude'] as double,
      (alarmJson['position'] as Map<String, dynamic>)['longitude'] as double,
    ),
    radius: alarmJson['radius'] as double,
    // active defaults to false
  );
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
