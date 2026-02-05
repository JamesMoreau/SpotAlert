import 'dart:math' as math;

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
      child: Stack(
        alignment: .center,
        children: [
          CustomPaint(size: Size(diameter, diameter), painter: GridPainter()),
          AnimatedBuilder(
            animation: controller,
            builder: (_, child) => Transform.rotate(angle: controller.value * 2 * pi, child: child),
            child: CustomPaint(
              size: Size(diameter, diameter),
              painter: RadarPainter(color: widget.alarm.color.value),
            ),
          ),
        ],
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final Color color;

  const RadarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(.zero);
    final radius = size.shortestSide / 2;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: .4);
    canvas.drawCircle(center, radius, backgroundPaint);

    final paint = Paint()
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: .4), color.withValues(alpha: .8)],
        stops: const [
          1 / 3, // start of sweep (1/4 of circle)
          1, // bright edge
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.white;
    canvas.drawCircle(center, radius - ringPaint.strokeWidth / 2, ringPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => oldDelegate.color != color;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(.zero);
    final radius = size.shortestSide / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;

    canvas
      ..drawCircle(center, radius / 2, paint)
      ..drawLine(center - Offset(radius, 0), center + Offset(radius, 0), paint) // NS
      ..drawLine(center - Offset(0, radius), center + Offset(0, radius), paint); // EW
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

double metersToScreenPixels(MapCamera camera, LatLng point, double meters) {
  //TODO: is this robust? ie, works for any size, zoom.
  final origin = camera.getOffsetFromOrigin(point);
  final offsetPoint = const Distance().offset(point, meters, 180); // south
  final offset = camera.getOffsetFromOrigin(offsetPoint);

  return (origin - offset).distance;
}
