import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:loca_alert/loca_alert.dart';
import 'package:loca_alert/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => LocaAlert(),
      builder: (locaAlert) {
        return SafeArea(
          child: Scrollbar(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(locaAlert.packageInfo.appName),
                    subtitle: Text('Version: ${locaAlert.packageInfo.version}'),
                    trailing: const Icon(Icons.info_rounded),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Vibration'),
                    trailing: Switch(
                      value: locaAlert.vibrationSetting,
                      thumbIcon: thumbIcon,
                      onChanged: (value) {
                        locaAlert.vibrationSetting = value;
                        locaAlert.setState();
                        saveSettings(locaAlert);
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Show Closest Alarm'),
                    trailing: Switch(
                      value: locaAlert.showClosestNonVisibleAlarmSetting,
                      onChanged: (value) {
                        locaAlert.showClosestNonVisibleAlarmSetting = value;
                        locaAlert.setState();
                        saveSettings(locaAlert);
                      },
                      thumbIcon: thumbIcon,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Open Settings'),
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
                      var uri = Uri.parse(appStoreUrl);
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

                      await locaAlert.mapTileCacheStore?.clean();
                      debugPrintInfo('Map tile cache cleared.');

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
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: const Text('Author:'),
                    subtitle: const Text(author),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () async {
                      var uri = Uri.parse(websiteUrl);
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
