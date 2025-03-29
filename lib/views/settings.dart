import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:loca_alert/constants.dart';
import 'package:loca_alert/loca_alert_state.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => LocaAlertState(),
      builder: (state) {
        return SafeArea(
          child: Scrollbar(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(state.appName),
                    subtitle: Text('Version: ${state.version}'),
                    trailing: const Icon(Icons.info_rounded),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Vibration'),
                    trailing: Switch(
                      value: state.vibration,
                      thumbIcon: thumbIcon,
                      onChanged: (value) {
                        changeVibration(newValue: value);
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Show Closest Off-Screen Alarm'),
                    trailing: Switch(
                      value: state.showClosestOffScreenAlarm,
                      onChanged: (value) {
                        changeShowClosestOffScreenAlarm(newValue: value);
                      },
                      thumbIcon: thumbIcon,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('App Settings'),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: () => AppSettings.openAppSettings(type: AppSettingsType.location),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Review App'),
                    trailing: const Icon(Icons.feedback_rounded),
                    onTap: () async {
                      var url = 'https://apps.apple.com/app/id$appleID';
                      var uri = Uri.parse(url);
                      var canLaunch = await canLaunchUrl(uri);
                      if (!canLaunch) {
                        if (kDebugMode) print('Cannot launch url.');
                        return;
                      }

                      debugPrintInfo('Opening app store page for feedback.');
                      await launchUrl(uri);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Clear Map Cache'),
                    subtitle: const Text('This can free up storage on your device.'),
                    trailing: const Icon(Icons.delete_rounded),
                    onTap: () async {
                      var scaffoldMessenger = ScaffoldMessenger.of(context); // Don't use Scaffold.of(context) across async gaps (according to flutter).

                      await state.mapTileCacheStore?.clean();
                      debugPrintSuccess('Map tile cache cleared.');

                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Container(padding: const EdgeInsets.all(8), child: const Text('Map tile cache cleared.')),
                          duration: const Duration(seconds: 3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                  ),
                ),
                if (kDebugMode)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: ListTile(
                      title: const Text('DEBUG: Print Alarms In Storage.'),
                      trailing: const Icon(Icons.alarm_rounded),
                      onTap: () async {
                        var directory = await getApplicationDocumentsDirectory();
                        var alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
                        var alarmsFile = File(alarmsPath);

                        if (!alarmsFile.existsSync()) {
                          debugPrintWarning('No alarms file found in storage.');
                          return;
                        }

                        var alarmJsons = await alarmsFile.readAsString();
                        if (alarmJsons.isEmpty) {
                          debugPrintInfo('No alarms found in storage.');
                          return;
                        }

                        debugPrintInfo('Alarms found in storage: $alarmJsons');
                      },
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
