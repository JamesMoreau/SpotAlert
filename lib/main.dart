import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/spot_alert_state.dart';

/*
TODO: 
  add "approximate arrival time" indicator.
*/

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    const maxConnections = 8;
    final client = super.createHttpClient(context)..maxConnectionsPerHost = maxConnections;
    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isIOS) {
    logger.e('This app is not supported on this platform. Supported platforms: iOS');
    await SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    return;
  }

  await Alarm.init();

  await SystemChrome.setPreferredOrientations([.portraitUp]);

  await NativeGeofenceManager.instance.initialize();

  // Set up http overrides. This is needed to increase the number of concurrent http requests allowed. This helps with the map tiles loading.
  HttpOverrides.global = MyHttpOverrides();

  // Initialize map tile cache.
  final documentsDir = await getApplicationDocumentsDirectory();
  try {
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDir.path);
  } on Exception catch (error, stackTrace) {
    logger.i('FMTC initialization failed: $error\n$stackTrace');

    // Attempt to delete the corrupted FMTC directory.
    final fmtcDir = Directory(path.join(documentsDir.path, 'fmtc'));
    await fmtcDir.delete(recursive: true);

    // Retry FMTC initialization.
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDir.path);
  }
  await const FMTCStore(mapTileStoreName).manage.create();

  runApp(const App());
}
