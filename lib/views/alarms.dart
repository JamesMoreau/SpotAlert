import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/spot_alert_state.dart';

class AlarmsView extends StatelessWidget {
  const AlarmsView({super.key});

  void openAlarmEdit(BuildContext context, SpotAlert spotAlert, Alarm alarm) {
    debugPrintInfo('Editing alarm: ${alarm.name}, id: ${alarm.id}.');
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => EditAlarmDialog(alarm));
  }

  Future<void> addSampleAlarms(SpotAlert spotAlert) async {
    final sampleAlarms = [
      Alarm(name: 'Dublin', position: const LatLng(53.3498, -6.2603), radius: 2000, color: AvailableAlarmColors.green.value),
      Alarm(name: 'Montreal', position: const LatLng(45.5017, -73.5673), radius: 2000, color: AvailableAlarmColors.blue.value),
      Alarm(name: 'Osaka', position: const LatLng(34.6937, 135.5023), radius: 2000, color: AvailableAlarmColors.purple.value),
      Alarm(name: 'Saint Petersburg', position: const LatLng(59.9310, 30.3609), radius: 2000, color: AvailableAlarmColors.redAccent.value),
      Alarm(name: 'San Antonio', position: const LatLng(29.4241, -98.4936), radius: 2000, color: AvailableAlarmColors.orange.value),
    ];

    for (final a in sampleAlarms) {
      spotAlert.alarms.add(a);
      spotAlert.setState();

      final success = await setAlarmActiveState(spotAlert, a, setToActive: true);
      if (!success) break;
    }

    await saveAlarmsToStorage(spotAlert.alarms);
  }

  Future<bool> setAlarmActiveState(SpotAlert spotAlert, Alarm alarm, {required bool setToActive}) async {
    if (!setToActive) {
      final success = await deactivateAlarm(alarm);
      if (!success) {
        showMySnackBar('Failed to deactivate the alarm.');
        return false;
      }

      spotAlert.setState();
      await saveAlarmsToStorage(spotAlert.alarms);

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
                    leading: Icon(
                      Icons.pin_drop_rounded,
                      color: alarm.color,
                      size: 30,
                      shadows: solidOutlineShadows(color: Colors.white, radius: 2),
                    ),
                    subtitle: Text(alarm.position.toSexagesimal(), style: .new(fontSize: 9, color: Colors.grey[700])),
                    onLongPress: () => openAlarmEdit(context, spotAlert, alarm),
                    onTap: () => openAlarmEdit(context, spotAlert, alarm),
                    trailing: Switch(
                      value: alarm.active,
                      activeThumbColor: alarm.color,
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

class EditAlarmDialog extends StatefulWidget {
  final Alarm alarm;
  const EditAlarmDialog(this.alarm, {super.key});

  @override
  State<EditAlarmDialog> createState() => _EditAlarmDialogState();
}

class _EditAlarmDialogState extends State<EditAlarmDialog> {
  late final TextEditingController nameInput;
  late Color colorInput;

  @override
  void initState() {
    super.initState();
    nameInput = .new(text: widget.alarm.name);
    colorInput = widget.alarm.color;
  }

  @override
  void dispose() {
    nameInput.dispose();
    super.dispose();
  }

  Future<void> handleAlarmDeletion(SpotAlert spotAlert) async {
    final id = widget.alarm.id;

    final isActive = widget.alarm.active;
    if (isActive) {
      final success = await deactivateAlarm(widget.alarm);
      if (!success) {
        final message = 'Alarm $id could not be deactivated for deletion.';

        debugPrintError(message);

        showMySnackBar(message);
        return;
      }
    }

    spotAlert.alarms.removeWhere((a) => a.id == id);
    spotAlert.setState();

    await saveAlarmsToStorage(spotAlert.alarms);
  }

  Future<void> navigateToAlarm(BuildContext context, SpotAlert spotAlert) async {
    Navigator.pop(context); // Close the edit alarm bottom sheet.

    await navigateToView(spotAlert, .map);

    // Wait until map is ready before moving it.
    await spotAlert.mapIsReady.future;

    tryMoveMap(spotAlert, widget.alarm.position);
  }

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      // TODO: can we get rid of this? maybe by returning a value from the dialog?
      SpotAlert.new,
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
                        widget.alarm.update(name: nameInput.text.trim(), color: colorInput);
                        setState(() {});
                        spotAlert.setState();
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
                        controller: nameInput,
                        onChanged: (value) => setState(() {}),
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              nameInput.clear();
                              setState(() {});
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
                                backgroundColor: colorInput,
                                radius: 20,
                                child: const Icon(Icons.pin_drop_rounded, color: Colors.white),
                              ),
                            ),
                            for (final color in AvailableAlarmColors.values) ...[
                              Padding(
                                padding: const .all(8),
                                child: GestureDetector(
                                  onTap: () {
                                    colorInput = color.value;
                                    setState(() {});
                                  },
                                  child: CircleAvatar(
                                    backgroundColor: color.value,
                                    radius: 20,
                                    child: color.value == colorInput ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Position', style: .new(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      Text(widget.alarm.position.toSexagesimal(), style: const .new(fontWeight: .bold)),
                      const SizedBox(height: 10),
                      Align(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                          onPressed: () => navigateToAlarm(context, spotAlert),
                          icon: const Icon(Icons.navigate_next_rounded, color: Colors.white),
                          label: const Text('Go To Alarm', style: .new(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Radius / Size (in meters)', style: .new(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      Text(widget.alarm.radius.toInt().toString(), style: const .new(fontWeight: .bold)),
                      const SizedBox(height: 30),
                      Align(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: .circular(8),
                              side: const .new(color: Colors.redAccent, width: 2),
                            ),
                          ),
                          onPressed: () {
                            handleAlarmDeletion(spotAlert);
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

// for switch icons.
final WidgetStateProperty<Icon?> thumbIcon = WidgetStateProperty.resolveWith<Icon?>((states) {
  if (states.contains(WidgetState.selected)) return const Icon(Icons.check_rounded);
  return const Icon(Icons.close_rounded);
});
