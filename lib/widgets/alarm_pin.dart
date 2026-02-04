import 'package:flutter/material.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/models/alarm.dart';

class AlarmPin extends StatelessWidget {
  final Alarm alarm;

  const AlarmPin(this.alarm, {super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      alarm.active ? Icons.pin_drop_rounded : Icons.location_off_rounded,
      color: alarm.color.value,
      size: 30,
      shadows: solidOutlineShadows(color: Colors.white, radius: 2),
    );
  }
}
