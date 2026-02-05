import 'dart:math' as math;

import 'package:flutter/material.dart';

class AlarmCircle extends StatefulWidget {
  final double diameter;
  final Color color;
  final Duration sweepDuration;
  final double sweepAngle; // radians

  const AlarmCircle({
    required this.diameter,
    super.key,
    this.color = Colors.blue,
    this.sweepDuration = const Duration(seconds: 2),
    this.sweepAngle = math.pi / 4, // 45 degrees
  });

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
    return SizedBox(
      width: widget.diameter,
      height: widget.diameter,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) {
          return CustomPaint(
            painter: AlarmCirclePainter(progress: controller.value, color: widget.color, sweepAngle: widget.sweepAngle),
          );
        },
      ),
    );
  }
}

class AlarmCirclePainter extends CustomPainter {
  final double progress; // 0 -> 1
  final Color color;
  final double sweepAngle;

  AlarmCirclePainter({required this.progress, required this.color, required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(.zero);
    final radius = size.width / 2;

    // Outer soft boundary ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: .35);

    canvas.drawCircle(center, radius - 1, ringPaint);

    // Radar sweep
    final startAngle = (progress * math.pi * 2) - sweepAngle;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: .15), color.withValues(alpha: 0.45)],
        stops: const [0.0, 0.7, 1.0],
        transform: const GradientRotation(0),
      ).createShader(rect)
      ..blendMode = .plus;

    canvas.drawCircle(center, radius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant AlarmCirclePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.sweepAngle != sweepAngle;
  }
}
