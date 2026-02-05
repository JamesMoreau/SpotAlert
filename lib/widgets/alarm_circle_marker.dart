import 'package:flutter/material.dart';

class AlarmCircle extends StatefulWidget {
  final double size;
  final Color color;
  final bool active;

  const AlarmCircle({required this.size, required this.color, required this.active, super.key});

  @override
  State<AlarmCircle> createState() => _AlarmCircleState();
}

class _AlarmCircleState extends State<AlarmCircle> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> alpha;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: const .new(seconds: 2))..repeat(reverse: true);

    alpha = Tween(begin: .35, end: .6).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: .circle,
        color: widget.active ? widget.color.withValues(alpha: alpha.value) : widget.color.withValues(alpha: .25),
        border: .all(color: Colors.white, width: 2),
      ),
    );
  }
}
