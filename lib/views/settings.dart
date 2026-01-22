import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:june/june.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/spot_alert.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => SpotAlert(),
      builder: (spotAlert) {
        return SafeArea(
          child: Scrollbar(
            child: ListView(
              children: [
                Padding(
                  padding: const .all(8),
                  child: ListTile(
                    title: Text(spotAlert.packageInfo.appName),
                    subtitle: Text('Version: ${spotAlert.packageInfo.version}'),
                    trailing: const Icon(Icons.info_rounded),
                  ),
                ),
                Padding(
                  padding: const .all(8),
                  child: ListTile(
                    title: const Text('Open Settings'),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: () => AppSettings.openAppSettings(type: .location),
                  ),
                ),
                Padding(
                  padding: const .all(8),
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
                  padding: const .all(8),
                  child: ListTile(
                    title: const Text('Clear Map Cache'),
                    subtitle: const Text('This can free up storage on your device.'),
                    trailing: const Icon(Icons.delete_rounded),
                    onTap: () async {
                      var scaffoldMessenger = ScaffoldMessenger.of(context); // Don't use Scaffold.of(context) across async gaps (according to flutter).

                      var size = await const FMTCStore(mapTileStoreName).stats.size;
                      await const FMTCStore(mapTileStoreName).manage.reset();

                      var sizeInMegabytes = double.parse((size / (1024 * 1024)).toStringAsFixed(2));
                      var message = 'Map tile cache cleared. $sizeInMegabytes MB freed.';

                      debugPrintInfo(message);

                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          behavior: .floating,
                          content: Container(padding: const .all(8), child: Text(message)),
                          duration: const Duration(seconds: 3),
                          shape: RoundedRectangleBorder(borderRadius: .circular(10)),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const .all(8),
                  child: ListTile(
                    title: const Text('Author: $author'),
                    subtitle: RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: const [
                          TextSpan(text: 'If you like this app, consider supporting the author via '),
                          TextSpan(
                            text: 'Ko-fi',
                            style: .new(
                              decoration: .underline,
                            ),
                          ),
                          TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () async {
                      var uri = Uri.parse(kofi);
                      var canLaunch = await canLaunchUrl(uri);
                      if (!canLaunch) {
                        if (kDebugMode) print('Cannot launch url.');
                        return;
                      }

                      debugPrintInfo('Opening Ko-fi page.');
                      await launchUrl(uri);
                    },
                  ),
                ),
                if (kDebugMode)
                  Padding(
                    padding: const .all(8),
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
