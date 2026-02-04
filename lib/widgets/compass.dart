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
          final angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().

          userArrow = UserArrow(angle: angle, arrowRotation: arrowRotation, ellipseWidth: ellipseWidth, ellipseHeight: ellipseHeight);
        }

        // If no alarms are currently visible on screen, show an arrow pointing towards the closest alarm (if there is one).
        Widget? alarmArrow;
        final activeAlarms = alarms.where((a) => a.active).toList();
        final closestAlarm = getClosest(position, activeAlarms, (alarm) => alarm.position);
        if (closestAlarm != null) {
          final closestAlarmIsVisible = !camera.visibleBounds.contains(closestAlarm.position);
          if (closestAlarmIsVisible) {
            final arrowRotation = calculateAngleBetweenTwoPositions(MapCamera.of(context).center, closestAlarm.position);
            final angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().

            final label = closestAlarm.name.trim().isEmpty ? null : closestAlarm.name;

            alarmArrow = AlarmArrow(
              angle: angle,
              arrowRotation: arrowRotation,
              ellipseWidth: ellipseWidth,
              ellipseHeight: ellipseHeight,
              alarm: closestAlarm,
              label: label,
            );
          }
        }

        return IgnorePointer(
          child: Center(
            child: Stack(alignment: .center, children: [if (userArrow != null) userArrow, if (alarmArrow != null) alarmArrow]),
          ),
        );
      },
    );
  }
}

class UserArrow extends StatelessWidget {
  final double angle;
  final double arrowRotation;
  final double ellipseWidth;
  final double ellipseHeight;

  const UserArrow({required this.angle, required this.arrowRotation, required this.ellipseWidth, required this.ellipseHeight, super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        alignment: .center,
        children: [
          Transform.translate(
            offset: .new((ellipseWidth / 2) * cos(angle), (ellipseHeight / 2) * sin(angle)),
            child: Transform.rotate(
              angle: arrowRotation,
              child: Transform.rotate(
                angle: -pi / 2,
                child: const Icon(Icons.arrow_forward_ios, color: Colors.blueAccent, size: 28),
              ),
            ),
          ),
          Transform.translate(offset: .new((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)), child: const UserIcon()),
        ],
      ),
    );
  }
}

class AlarmArrow extends StatelessWidget {
  final double angle;
  final double arrowRotation;
  final double ellipseWidth;
  final double ellipseHeight;

  final String? label;
  final Alarm alarm;

  const AlarmArrow({
    required this.alarm,
    required this.angle,
    required this.arrowRotation,
    required this.ellipseWidth,
    required this.ellipseHeight,
    this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final angleIs9to3 = angle > 0 && angle < pi;

    return IgnorePointer(
      child: Stack(
        alignment: .center,
        children: [
          Transform.translate(
            offset: .new((ellipseWidth / 2) * cos(angle), (ellipseHeight / 2) * sin(angle)),
            child: Transform.rotate(
              angle: arrowRotation,
              child: Transform.rotate(
                angle: -pi / 2,
                child: Icon(Icons.arrow_forward_ios, color: alarm.color.value, size: 28),
              ),
            ),
          ),
          Transform.translate(offset: .new((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)), child: AlarmPin(alarm)),
          if (label != null) ...[
            Transform.translate(
              offset: .new((ellipseWidth / 2 - 26) * cos(angle), (ellipseHeight / 2 - 26) * sin(angle)),
              child: Transform.translate(
                // Move the text up or down depending on the angle to now overlap with the arrow.
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
