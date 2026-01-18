import 'package:flutter/material.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';

void showAlarmDialog(BuildContext context, Alarm triggeredAlarm) {
  showGeneralDialog<void>(
    context: context,
    pageBuilder: (context, a1, a2) => Dialog.fullscreen(
      child: Container(
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
                    const Text(
                      'Alarm Triggered',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'You have entered the radius of an alarm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Icon(Icons.alarm, size: 100, color: triggeredAlarm.color),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Text(triggeredAlarm.name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context), // Close the dialog
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(225, 70),
                        textStyle: const TextStyle(fontSize: 25),
                      ),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
