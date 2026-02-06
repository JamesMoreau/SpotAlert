import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/spot_alert_state.dart';
import 'package:uuid/uuid.dart';

/*
TODO: 
  - Update screenshots in app store and readme.
*/

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    const maxConnections = 8;
    final client = super.createHttpClient(context)..maxConnectionsPerHost = maxConnections;
    return client;
  }
}

const Uuid idGenerator = Uuid();

void debugPrintMessage(String message) {
  assert(() {
    debugPrint(message);
    return true;
  }());
}

void debugPrintInfo(String message) => debugPrintMessage('ℹ️ $message');
void debugPrintWarning(String message) => debugPrintMessage('⚠️ $message');
void debugPrintError(String message) => debugPrintMessage('❌ $message');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isIOS) {
    debugPrintError('This app is not supported on this platform. Supported platforms: iOS');
    await SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    return;
  }

  await SystemChrome.setPreferredOrientations([.portraitUp]);

  // Set up http overrides. This is needed to increase the number of concurrent http requests allowed. This helps with the map tiles loading.
  HttpOverrides.global = MyHttpOverrides();

  // Initialize map tile cache.
  final documentsDir = await getApplicationDocumentsDirectory();
  try {
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDir.path);
  } on Exception catch (error, stackTrace) {
    debugPrintInfo('FMTC initialization failed: $error\n$stackTrace');

    // Attempt to delete the corrupted FMTC directory.
    final fmtcDir = Directory(path.join(documentsDir.path, 'fmtc'));
    await fmtcDir.delete(recursive: true);

    // Retry FMTC initialization.
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDir.path);
  }
  await const FMTCStore(mapTileStoreName).manage.create();

  runApp(const App());

  final success = await FlutterLocalNotificationsPlugin().initialize(const InitializationSettings(iOS: .new()));
  final didInitialize = success ?? false;
  if (!didInitialize) {
    debugPrintError('Notifications unavailable (permission denied or initialization failed).');
  }
}
