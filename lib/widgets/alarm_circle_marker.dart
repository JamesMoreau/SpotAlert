import 'dart:math' as math;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/models/alarm.dart';

//TODO: this should have an inactive return path for inactive alarms.
class AlarmCircle extends StatefulWidget {
  final Alarm alarm;
  final Duration sweepDuration;
  final double sweepAngle; // radians

  const AlarmCircle({required this.alarm, super.key, this.sweepDuration = const Duration(seconds: 4), this.sweepAngle = math.pi / 4});

  @override
  State<AlarmCircle> createState() => _AlarmCircleState();
}

class _AlarmCircleState extends State<AlarmCircle> with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: widget.sweepDuration)..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final pixelRadius = metersToScreenPixels(camera, widget.alarm.position, widget.alarm.radius);
    final diameter = pixelRadius * 2;

    if (diameter <= 0) return const SizedBox.shrink();

    return SizedBox(
      width: diameter,
      height: diameter,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, child) => Transform.rotate(angle: controller.value * 2 * pi, child: child),
        child: CustomPaint(painter: AlarmCirclePainter(color: widget.alarm.color.value)),
      ),
    );
  }
}

class AlarmCirclePainter extends CustomPainter {
  final Color color;

  const AlarmCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(.zero);
    final radius = size.shortestSide / 2;

    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0), color.withValues(alpha: .35)],
        stops: const [
          0.75, // start of sweep (1/4 of circle)
          1.0,  // bright edge
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant AlarmCirclePainter oldDelegate) => oldDelegate.color != color;
}

double metersToScreenPixels(MapCamera camera, LatLng point, double meters) {
  //TODO: is this robust? ie, works for any size, zoom.
  final origin = camera.getOffsetFromOrigin(point);
  final offsetPoint = const Distance().offset(point, meters, 180); // south
  final offset = camera.getOffsetFromOrigin(offsetPoint);

  return (origin - offset).distance;
}
