import 'package:flutter/material.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/models/alarm.dart';

// TODO: make this alarm vibrate
void showAlarmDialog(NavigatorState navigator, Alarm triggeredAlarm) {
  showGeneralDialog<void>(
    context: navigator.context,
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
                    const Text('Alarm Triggered', style: .new(fontSize: 30, fontWeight: .w300)),
                    const SizedBox(height: 16),
                    Icon(Icons.alarm, size: 100, color: triggeredAlarm.color.value),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Text(triggeredAlarm.name, style: const .new(fontSize: 30, fontWeight: .bold)),
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
      ),
    ),
  );
}
