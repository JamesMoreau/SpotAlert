import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:loca_alert/constants.dart';
import 'package:loca_alert/loca_alert.dart';
import 'package:loca_alert/models/alarm.dart';
import 'package:vibration/vibration.dart';

void showAlarmDialog(BuildContext context, String alarmId) {
	var state = June.getState(() => LocaAlert());
	var alarm = getAlarmById(state, alarmId);

	if (alarm == null) {
		debugPrintError('Unable to retrieve triggered alarm.');
		state.alarmIsCurrentlyTriggered = false;
		return;
	}

	void deactivateAlarmAndCloseDialog(BuildContext context) {
		var dismissedAlarm = Alarm(
			name: alarm.name,
			position: alarm.position,
			radius: alarm.radius,
			color: alarm.color,
			active: false, // deactivate the alarm
		);
		updateAlarmById(state, alarmId, dismissedAlarm);
		if (state.vibration) Vibration.cancel();
		Navigator.pop(context);
		state.alarmIsCurrentlyTriggered = false;
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
											onPressed: () => deactivateAlarmAndCloseDialog(context),
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
