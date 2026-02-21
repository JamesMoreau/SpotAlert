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
              Icon(
                Icons.info_outline_rounded,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const Text(
                'Place alarms by tapping the marker button. Use the lock button to follow or unfollow your location.',
                textAlign: TextAlign.center,
              ),
              const Text(
                'Staying on the map for long periods may drain your battery.',
                textAlign: TextAlign.center,
              ),
              const Text(
                'To use the app in the background: set location access to "While Using" or "Always", enable notifications, and make sure Silent Mode is off.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
