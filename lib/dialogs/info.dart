import 'package:flutter/material.dart';

class InfoDialog extends StatelessWidget {
  const InfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const .all(24),
        child: SingleChildScrollView(
          child: Column(
            spacing: 15,
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              Icon(Icons.info_outline_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
              const Text(
                'Here you can place new alarms by tapping the marker button. You can also follow / unfollow your location by tapping the lock button.',
                textAlign: .center,
              ),
              const Text('Staying on the map view for long periods of time may drain your battery.', textAlign: .center),
              const Text('Set location permissions to "While Using" or "Always" and enable notifications to use the app when running in background.', textAlign: .center),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }
}
