import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/models/alarm.dart';

class AlarmCircle extends StatefulWidget {
  final Alarm alarm;
  final Duration sweepDuration;
  final double sweepAngle; // radians

  const AlarmCircle({required this.alarm, super.key, this.sweepDuration = const Duration(seconds: 2), this.sweepAngle = math.pi / 4});

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

    // Nothing to draw if we're effectively invisible
    if (diameter <= 0) return const SizedBox.shrink();

    return SizedBox(
      width: diameter,
      height: diameter,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => CustomPaint(
          painter: AlarmCirclePainter(progress: controller.value, color: widget.alarm.color.value, sweepAngle: widget.sweepAngle),
        ),
      ),
    );
  }
}

class AlarmCirclePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double sweepAngle;

  const AlarmCirclePainter({required this.progress, required this.color, required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final angle = progress * math.pi * 2;

    // Base fill
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.3);

    canvas.drawCircle(center, radius, fillPaint);

    // Boundary ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;

    canvas.drawCircle(center, radius - 1, ringPaint);

    // Sweeping arm
    final armPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(rect, angle, sweepAngle, false, armPaint);
  }

  @override
  bool shouldRepaint(covariant AlarmCirclePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.sweepAngle != sweepAngle;
  }
}

double metersToScreenPixels(MapCamera camera, LatLng point, double meters) {
  //TODO: is this robust? ie, works for any size, zoom.
  final origin = camera.getOffsetFromOrigin(point);
  final offsetPoint = const Distance().offset(point, meters, 180); // south
  final offset = camera.getOffsetFromOrigin(offsetPoint);

  return (origin - offset).distance;
}
