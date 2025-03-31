import 'package:flutter/material.dart';
import 'package:loca_alert/loca_alert.dart';
import 'package:loca_alert/main.dart';

void showAlarmDialog(BuildContext context, LocaAlert state) {
  if (state.triggeredAlarmId == null) {
    debugPrintError('showAlarmDialog() was called but there is no triggered alarm id.');
    return;
  }
  
  var alarm = getAlarmById(state, state.triggeredAlarmId!);
  if (alarm == null) {
    debugPrintError('Unable to retrieve triggered alarm with id: ${state.triggeredAlarmId}.');
    state.triggeredAlarmId = null;
    return;
  }

  showGeneralDialog<void>(
    context: context,
    pageBuilder: (context, a1, a2) => Dialog.fullscreen(
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        color: paleBlue,
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    Icon(Icons.alarm, size: 100, color: alarm.color),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Text(alarm.name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // Close the dialog
                        state.triggeredAlarmId = null;
                        Navigator.pop(context);
                      },
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
