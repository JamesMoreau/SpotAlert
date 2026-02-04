import 'package:flutter/material.dart';

class OpenStreetMapAttribution extends StatelessWidget {
  const OpenStreetMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const .all(3),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: .circular(8)),
        child: const Text('© OpenStreetMap contributors'),
      ),
    );
  }
}
