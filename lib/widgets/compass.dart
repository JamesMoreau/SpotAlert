import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/widgets/alarm_pin.dart';
import 'package:spot_alert/widgets/user_icon.dart';

class Compass extends StatelessWidget {
  final Stream<LatLng> userPositionStream;
  final List<Alarm> alarms;

  const Compass({required this.userPositionStream, required this.alarms, super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final ellipseWidth = screenSize.width * .8;
    final ellipseHeight = screenSize.height * .65;

    final layout = CompassLayout(
      size: Size(ellipseWidth, ellipseHeight),
      bounds: Rect.fromCenter(center: .zero, width: ellipseWidth, height: ellipseHeight),
    );

    return StreamBuilder(
      stream: userPositionStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        final position = snapshot.data;

        // Nothing to show for compass if user position not available
        if (position == null) return const SizedBox.shrink();

        final camera = MapCamera.of(context);

        // If the user's position exists but is not visible, show an arrow pointing towards them.
        Widget? userArrow;
        final userIsVisible = camera.visibleBounds.contains(position);
        if (!userIsVisible) {
          final arrowRotation = calculateAngleBetweenTwoPositions(camera.center, position);
          userArrow = UserArrow(layout: layout, direction: arrowRotation);
        }

        // If no alarms are currently visible on screen, show an arrow pointing towards the closest alarm (if there is one).
        Widget? alarmArrow;
        final activeAlarms = alarms.where((a) => a.active).toList();
        final closestActiveAlarm = getClosest(position, activeAlarms, (alarm) => alarm.position);
        if (closestActiveAlarm != null) {
          final closestAlarmIsVisible = !camera.visibleBounds.contains(closestActiveAlarm.position);
          if (closestAlarmIsVisible) {
            final arrowRotation = calculateAngleBetweenTwoPositions(camera.center, closestActiveAlarm.position);
            final label = closestActiveAlarm.name.trim().isEmpty ? null : closestActiveAlarm.name;
            
            alarmArrow = AlarmArrow(layout: layout, direction: arrowRotation, alarm: closestActiveAlarm, label: label);
          }
        }

        return IgnorePointer(
          child: Center(
            child: Stack(alignment: .center, children: [ ?userArrow, ?alarmArrow]),
          ),
        );
      },
    );
  }
}

class CompassLayout {
  final Size size;
  final Rect bounds;

  const CompassLayout({required this.size, required this.bounds});

  Offset positionForAngle(double angle, {double inset = 0}) {
    final a = size.width / 2 - inset;
    final b = size.height / 2 - inset;

    return .new(a * cos(angle), b * sin(angle));
  }
}

class UserArrow extends StatelessWidget {
  final CompassLayout layout;
  final double direction; // world-space direction in radians

  const UserArrow({required this.layout, required this.direction, super.key});

  @override
  Widget build(BuildContext context) {
    // Convert world direction -> screen angle
    final angle = (direction + 3 * pi / 2) % (2 * pi);

    return IgnorePointer(
      child: Stack(
        alignment: .center,
        children: [
          Transform.translate(
            offset: layout.positionForAngle(angle),
            child: Transform.rotate(
              angle: direction - pi / 2,
              child: const Icon(Icons.arrow_forward_ios, color: Colors.blueAccent, size: 28),
            ),
          ),
          Transform.translate(offset: layout.positionForAngle(angle, inset: 24), child: const UserIcon()),
        ],
      ),
    );
  }
}

class AlarmArrow extends StatelessWidget {
  final CompassLayout layout;
  final double direction;
  final Alarm alarm;
  final String? label;

  const AlarmArrow({required this.layout, required this.direction, required this.alarm, this.label, super.key});

  @override
  Widget build(BuildContext context) {
    final angle = (direction + 3 * pi / 2) % (2 * pi);
    final angleIs9to3 = angle > 0 && angle < pi;

    return IgnorePointer(
      child: Stack(
        alignment: .center,
        children: [
          Transform.translate(
            offset: layout.positionForAngle(angle),
            child: Transform.rotate(
              angle: direction - pi / 2,
              child: Icon(Icons.arrow_forward_ios, color: alarm.color.value, size: 28),
            ),
          ),
          Transform.translate(offset: layout.positionForAngle(angle, inset: 24), child: AlarmPin(alarm)),
          if (label != null)
            Transform.translate(
              offset: layout.positionForAngle(angle, inset: 26),
              child: Transform.translate(
                offset: .new(0, angleIs9to3 ? -22 : 22),
                child: Container(
                  constraints: const .new(maxWidth: 100),
                  padding: const .symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: paleBlue.withValues(alpha: .7), borderRadius: .circular(8)),
                  child: Text(label!, style: const .new(fontSize: 10), overflow: .ellipsis, maxLines: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
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

double calculateAngleBetweenTwoPositions(LatLng from, LatLng to) => atan2(to.longitude - from.longitude, to.latitude - from.latitude);
