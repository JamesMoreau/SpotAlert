import 'package:flutter/material.dart';
import 'package:spot_alert/models/alarm.dart';

sealed class EditAlarmResult {
  const EditAlarmResult();
}

class Save extends EditAlarmResult {
  final String newName;
  final AlarmColor newColor;
  const Save(this.newName, this.newColor);
}

class Delete extends EditAlarmResult {
  const Delete();
}

class Cancel extends EditAlarmResult {
  const Cancel();
}

class NavigateTo extends EditAlarmResult {
  const NavigateTo();
}

class EditAlarm extends StatefulWidget {
  final Alarm alarm;
  const EditAlarm(this.alarm, {super.key});

  @override
  State<EditAlarm> createState() => _EditAlarmState();
}

class _EditAlarmState extends State<EditAlarm> {
  late final TextEditingController nameInput;
  late AlarmColor colorInput;

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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context, const Cancel())),
                const Text('Edit Alarm', style: .new(fontSize: 18, fontWeight: .bold)),
                TextButton(child: const Text('Save'), onPressed: () => Navigator.pop(context, Save(nameInput.text.trim(), colorInput))),
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
                            backgroundColor: colorInput.value,
                            radius: 20,
                            child: const Icon(Icons.pin_drop_rounded, color: Colors.white),
                          ),
                        ),
                        for (final color in AlarmColor.values) ...[
                          Padding(
                            padding: const .all(8),
                            child: GestureDetector(
                              onTap: () {
                                colorInput = color;
                                setState(() {});
                              },
                              child: CircleAvatar(
                                backgroundColor: color.value,
                                radius: 20,
                                child: color == colorInput ? const Icon(Icons.check_rounded, color: Colors.white) : null,
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
                      onPressed: () => Navigator.pop(context, const NavigateTo()),
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
                      onPressed: () => Navigator.pop(context, const Delete()),
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
  }
}
