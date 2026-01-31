import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:june/june.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/spot_alert_state.dart';
import 'package:url_launcher/url_launcher.dart';

const author = 'James Moreau';
const kofi = 'https://ko-fi.com/jamesmoreau';
const appStoreUrl = 'https://apps.apple.com/app/id6478944468';

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
                      final uri = Uri.parse(appStoreUrl);
                      final canLaunch = await canLaunchUrl(uri);
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
                      final size = await const FMTCStore(mapTileStoreName).stats.size;
                      await const FMTCStore(mapTileStoreName).manage.reset();

                      final sizeInMegabytes = double.parse((size / (1024 * 1024)).toStringAsFixed(2));
                      final message = 'Map tile cache cleared. $sizeInMegabytes MB freed.';

                      debugPrintInfo(message);

                      showMySnackBar(message);
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
                            style: .new(decoration: .underline),
                          ),
                          TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () async {
                      final uri = Uri.parse(kofi);
                      final canLaunch = await canLaunchUrl(uri);
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
                        final directory = await getApplicationDocumentsDirectory();
                        final alarmsPath = '${directory.path}${Platform.pathSeparator}$alarmsFilename';
                        final alarmsFile = File(alarmsPath);

                        if (!alarmsFile.existsSync()) {
                          debugPrintWarning('No alarms file found in storage.');
                          return;
                        }

                        final alarmJsons = await alarmsFile.readAsString();
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
