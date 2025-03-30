import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/loca_alert.dart';
import 'package:loca_alert/main.dart';

class Alarm {
  String id;
  String name;
  Color color;
  LatLng position;
  double radius; // Meters
  bool active;

  Alarm({
    required this.name,
    required this.position,
    required this.radius,
    String? id,
    Color? color,
    this.active = true,
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
    'active': alarm.active,
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
    active: alarmJson['active'] as bool,
  );
}
