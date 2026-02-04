import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/dialogs/edit_alarm.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/spot_alert_state.dart';
import 'package:spot_alert/widgets/alarm_pin.dart';

class AlarmsView extends StatelessWidget {
  const AlarmsView({super.key});

  Future<void> handleAlarmEdit(BuildContext context, SpotAlert spotAlert, Alarm alarm) async {
    debugPrintInfo('Editing alarm: ${alarm.name}, id: ${alarm.id}.');

    final result = await showModalBottomSheet<EditAlarmResult>(context: context, isScrollControlled: true, builder: (_) => EditAlarm(alarm));

    if (result == null) return; // user dismissed the sheet

    switch (result) {
      case Save():
        alarm.update(name: result.newName, color: result.newColor);
        spotAlert.setState();
        await saveAlarmsToStorage(spotAlert);
      case NavigateTo():
        await navigateToView(spotAlert, .map);

        // Wait until map is ready before moving it.
        await spotAlert.mapIsReady.future;

        tryMoveMap(spotAlert, alarm.position);
      case Delete():
        final isActive = alarm.active;
        if (isActive) {
          final success = await deactivateAlarm(alarm);
          if (!success) {
            final message = 'Alarm ${alarm.id} could not be deactivated for deletion.';

            debugPrintError(message);

            showMySnackBar(message);
            return;
          }
        }

        spotAlert.alarms.removeWhere((a) => a.id == alarm.id);
        spotAlert.setState();

        await saveAlarmsToStorage(spotAlert);
      case Cancel():
        // Do nothing.
        break;
    }
  }

  Future<void> addSampleAlarms(SpotAlert spotAlert) async {
    final sampleAlarms = [
      Alarm(name: 'Dublin', position: const LatLng(53.3498, -6.2603), radius: 2000, color: AlarmColor.green),
      Alarm(name: 'Montreal', position: const LatLng(45.5017, -73.5673), radius: 2000, color: AlarmColor.blue),
      Alarm(name: 'Osaka', position: const LatLng(34.6937, 135.5023), radius: 2000, color: AlarmColor.purple),
      Alarm(name: 'Saint Petersburg', position: const LatLng(59.9310, 30.3609), radius: 2000, color: AlarmColor.redAccent),
      Alarm(name: 'San Antonio', position: const LatLng(29.4241, -98.4936), radius: 2000, color: AlarmColor.orange),
    ];

    for (final a in sampleAlarms) {
      spotAlert.alarms.add(a);
      spotAlert.setState();

      final success = await setAlarmActiveState(spotAlert, a, setToActive: true);
      if (!success) break;
    }

    await saveAlarmsToStorage(spotAlert);
  }

  Future<bool> setAlarmActiveState(SpotAlert spotAlert, Alarm alarm, {required bool setToActive}) async {
    if (!setToActive) {
      final success = await deactivateAlarm(alarm);
      if (!success) {
        showMySnackBar('Failed to deactivate the alarm.');
        return false;
      }

      spotAlert.setState();
      await saveAlarmsToStorage(spotAlert);

      return true;
    }

    final result = await activateAlarm(alarm);

    String? message;
    switch (result) {
      case .success:
        spotAlert.setState();
        return true;

      case .limitReached:
        message = 'Maximum number of geofences allowed by iOS reached. Turn off one to add another.';

      case .failed:
        message = 'Failed to activate the alarm.';
    }

    showMySnackBar(message);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      SpotAlert.new,
      builder: (spotAlert) {
        if (spotAlert.alarms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: .center,
              children: [
                const Text('No alarms.'),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                  onPressed: () => addSampleAlarms(spotAlert),
                  child: const Text('Add Some Alarms', style: .new(color: Colors.white)),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Scrollbar(
            child: ListView.builder(
              itemCount: spotAlert.alarms.length,
              itemBuilder: (context, index) {
                final alarm = spotAlert.alarms[index];
                return Padding(
                  padding: const .all(8),
                  child: ListTile(
                    title: Text(alarm.name, maxLines: 1, overflow: .ellipsis),
                    leading: AlarmPin(alarm),
                    subtitle: Text(alarm.position.toSexagesimal(), style: .new(fontSize: 9, color: Colors.grey[700])),
                    onLongPress: () => handleAlarmEdit(context, spotAlert, alarm),
                    onTap: () => handleAlarmEdit(context, spotAlert, alarm),
                    trailing: Switch(
                      value: alarm.active,
                      activeThumbColor: alarm.color.value,
                      thumbIcon: thumbIcon,
                      onChanged: (value) => setAlarmActiveState(spotAlert, alarm, setToActive: value),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// for switch icons.
final WidgetStateProperty<Icon?> thumbIcon = WidgetStateProperty.resolveWith<Icon?>((states) {
  if (states.contains(WidgetState.selected)) return const Icon(Icons.check_rounded);
  return const Icon(Icons.close_rounded);
});
