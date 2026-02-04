import 'package:flutter/material.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/models/alarm.dart';

class TriggeredAlarmDialog extends StatelessWidget {
  final Alarm triggered;

  const TriggeredAlarmDialog(this.triggered, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      color: paleBlue,
      padding: const .all(20),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: .center,
                children: [
                  const Text('Alarm Triggered', style: .new(fontSize: 30, fontWeight: .w300)),
                  const SizedBox(height: 16),
                  WiggleWidget(child: Icon(Icons.alarm, size: 100, color: triggered.color.value)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Text(triggered.name, style: const .new(fontSize: 30, fontWeight: .bold)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Close the dialog
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(225, 70),
                      textStyle: const .new(fontSize: 25),
                    ),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WiggleWidget extends StatefulWidget {
  final Widget child;

  const WiggleWidget({required this.child, super.key});

  @override
  State<WiggleWidget> createState() => _WiggleWidgetState();
}

class _WiggleWidgetState extends State<WiggleWidget> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> rotation;
  late final Animation<double> offset;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(vsync: this, duration: const .new(milliseconds: 800))..repeat(reverse: true);
    rotation = Tween<double>(begin: -0.1, end: 0.1).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    offset = Tween<double>(begin: -6, end: 6).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        return Transform.translate(
          offset: Offset(offset.value, 0),
          child: Transform.rotate(angle: rotation.value, child: child),
        );
      },
      child: widget.child,
    );
  }
}
