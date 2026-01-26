import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/spot_alert.dart';

class AlarmsView extends StatelessWidget {
  const AlarmsView({super.key});

  void openAlarmEdit(BuildContext context, SpotAlert spotAlert, Alarm alarm) {
    debugPrintInfo('Editing alarm: ${alarm.name}, id: ${alarm.id}.');

    // Copy the alarm to the buffer alarm. We don't do this inside the edit widget to avoid rebuilds resetting the buffer state.
    spotAlert.editAlarm = alarm;
    spotAlert.colorInput = alarm.color;
    spotAlert.nameInput.text = alarm.name;

    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => const EditAlarmDialog());
  }

  Future<void> addSampleAlarms(SpotAlert spotAlert) async {
    var sampleAlarms = [
      Alarm(name: 'Dublin', position: const LatLng(53.3498, -6.2603), radius: 2000, color: AvailableAlarmColors.green.value),
      Alarm(name: 'Montreal', position: const LatLng(45.5017, -73.5673), radius: 2000, color: AvailableAlarmColors.blue.value),
      Alarm(name: 'Osaka', position: const LatLng(34.6937, 135.5023), radius: 2000, color: AvailableAlarmColors.purple.value),
      Alarm(name: 'Saint Petersburg', position: const LatLng(59.9310, 30.3609), radius: 2000, color: AvailableAlarmColors.redAccent.value),
      Alarm(name: 'San Antonio', position: const LatLng(29.4241, -98.4936), radius: 2000, color: AvailableAlarmColors.orange.value),
    ];

    for (var a in sampleAlarms) {
      await addAlarm(spotAlert, a);
      var success = await setAlarmActiveState(spotAlert, a, isActive: true);
      if (!success) break;
    }
  }

  Future<bool> setAlarmActiveState(SpotAlert spotAlert, Alarm alarm, {required bool isActive}) async {
    if (!isActive) {
      await deactivateAlarm(spotAlert, alarm);
      return true;
    }

    var result = await activateAlarm(spotAlert, alarm);

    String? message;
    switch (result) {
      case .success:
        return true;

      case .limitReached:
        message = 'Maximum number of geofences allowed by iOS reached. Turn off one to add another.';

      case .failed:
        message = 'Failed to activate the alarm.';
    }

    ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
      .new(
        behavior: .floating,
        content: Padding(padding: const .all(8), child: Text(message)),
        shape: RoundedRectangleBorder(borderRadius: .circular(10)),
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => SpotAlert(),
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
                var alarm = spotAlert.alarms[index];
                return Padding(
                  padding: const .all(8),
                  child: ListTile(
                    title: Text(alarm.name, maxLines: 1, overflow: .ellipsis),
                    leading: Icon(Icons.pin_drop_rounded, color: alarm.color, size: 30),
                    subtitle: Text(alarm.position.toSexagesimal(), style: .new(fontSize: 9, color: Colors.grey[700])),
                    onLongPress: () => openAlarmEdit(context, spotAlert, alarm),
                    onTap: () => openAlarmEdit(context, spotAlert, alarm),
                    trailing: Switch(
                      value: alarm.active,
                      activeThumbColor: alarm.color,
                      thumbIcon: thumbIcon,
                      onChanged: (value) => setAlarmActiveState(spotAlert, alarm, isActive: value),
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

class EditAlarmDialog extends StatelessWidget {
  const EditAlarmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => SpotAlert(),
      builder: (spotAlert) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: Padding(
            padding: const .symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: .spaceBetween,
                  children: [
                    TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
                    const Text('Edit Alarm', style: .new(fontSize: 18, fontWeight: .bold)),
                    TextButton(
                      child: const Text('Save'),
                      onPressed: () {
                        // Replace the actual alarm data with the buffer data.
                        updateAndSaveAlarm(spotAlert, spotAlert.editAlarm, newName: spotAlert.nameInput.text.trim(), newColor: spotAlert.colorInput);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: ListView(
                    children: [
                      Text('Name', style: .new(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      TextFormField(
                        textAlign: .center,
                        controller: spotAlert.nameInput,
                        onChanged: (value) => spotAlert.setState(),
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              spotAlert.nameInput.clear();
                              spotAlert.setState();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Color', style: .new(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      SingleChildScrollView(
                        scrollDirection: .horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const .all(8),
                              child: CircleAvatar(
                                backgroundColor: spotAlert.colorInput,
                                radius: 20,
                                child: const Icon(Icons.pin_drop_rounded, color: Colors.white),
                              ),
                            ),
                            for (var color in AvailableAlarmColors.values) ...[
                              Padding(
                                padding: const .all(8),
                                child: GestureDetector(
                                  onTap: () {
                                    spotAlert.colorInput = color.value;
                                    spotAlert.setState();
                                  },
                                  child: CircleAvatar(
                                    backgroundColor: color.value,
                                    radius: 20,
                                    child: color.value == spotAlert.colorInput ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Position', style: .new(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      Text(spotAlert.editAlarm.position.toSexagesimal(), style: const .new(fontWeight: .bold)),
                      const SizedBox(height: 10),
                      Align(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                          onPressed: () async {
                            Navigator.pop(context); // Close the edit alarm bottom sheet.
                            navigateToView(spotAlert, .map);

                            // This is a hack but we need to be sure that map controller is attached before moving.
                            await Future.doWhile(() async {
                              if (spotAlert.mapControllerIsAttached) return false;
                              await Future<void>.delayed(const Duration(milliseconds: 10));
                              return true;
                            });

                            var position = spotAlert.editAlarm.position;
                            spotAlert.mapController.move(position, initialZoom);
                          },
                          icon: const Icon(Icons.navigate_next_rounded, color: Colors.white),
                          label: const Text('Go To Alarm', style: .new(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Radius / Size (in meters)', style: .new(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      Text(spotAlert.editAlarm.radius.toInt().toString(), style: const .new(fontWeight: .bold)),
                      const SizedBox(height: 30),
                      Align(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: .circular(8),
                              side: const BorderSide(color: Colors.redAccent, width: 2),
                            ),
                          ),
                          onPressed: () {
                            var isActive = spotAlert.editAlarm.active;
                            if (isActive) {
                              deactivateAlarm(spotAlert, spotAlert.editAlarm);
                            }

                            var id = spotAlert.editAlarm.id;
                            var ok = deleteAlarmById(spotAlert, id);
                            if (!ok) {
                              debugPrintError('Alarm $id could not be deleted.');
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('Delete Alarm', style: .new(color: Colors.redAccent)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
