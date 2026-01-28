import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:june/june.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/spot_alert.dart';
import 'package:spot_alert/views/alarms.dart';
import 'package:spot_alert/views/map.dart';
import 'package:spot_alert/views/settings.dart';
import 'package:uuid/uuid.dart';

/*
TODO: 
  - ask for permissions to notification and location at startup.
  - should be able to remove position from the app state and just listen to the stream.
  - KNOWN ISSUE: iOS: After reboot, the first geofence event is triggered twice, one immediatly after the other. We recommend checking the last trigger time of a geofence in your app to discard duplicates.
  - add something cute to the app like a cartoon animal or something.
  - Update screenshots in app store and readme.
  - startup screen icon.
*/

enum AvailableAlarmColors {
  blue(Colors.blue),
  green(Colors.green),
  orange(Colors.orange),
  redAccent(Colors.redAccent),
  purple(Colors.purple),
  pink(Colors.pink),
  teal(Colors.teal),
  brown(Colors.brown),
  indigo(Colors.indigo),
  amber(Colors.amber),
  grey(Colors.grey),
  black(Colors.black);

  const AvailableAlarmColors(this.value);
  final Color value;
}

ThemeData spotAlertTheme = .new(
  colorScheme: const .new(
    brightness: .light,
    primary: Color(0xff006493),
    onPrimary: Colors.white,
    primaryContainer: .fromARGB(255, 216, 237, 255),
    onPrimaryContainer: Color(0xff001e30),
    secondary: Color(0xff50606e),
    onSecondary: Color(0xffffffff),
    secondaryContainer: Color(0xffd3e5f5),
    onSecondaryContainer: Color(0xff0c1d29),
    tertiary: Color(0xff65587b),
    onTertiary: Color(0xffffffff),
    tertiaryContainer: Color(0xffebddff),
    onTertiaryContainer: Color(0xff201634),
    error: Color(0xffba1a1a),
    onError: Colors.white,
    errorContainer: Color(0xffffdad6),
    onErrorContainer: Color(0xff410002),
    surface: Color(0xfffcfcff),
    onSurface: Color(0xff1a1c1e),
    surfaceContainerHighest: Color(0xffdde3ea),
    onSurfaceVariant: Color(0xff41474d),
    outline: Color(0xff72787e),
    outlineVariant: Color(0xffc1c7ce),
    inverseSurface: Color(0xff2e3133),
    onInverseSurface: Color(0xfff0f0f3),
    inversePrimary: Color(0xff8dcdff),
    surfaceTint: Color(0xff006493),
  ),
  listTileTheme: .new(
    contentPadding: const .all(25),
    tileColor: const .fromARGB(255, 234, 239, 246), // Background color of the ListTile
    shape: RoundedRectangleBorder(borderRadius: .circular(8)),
  ),
  sliderTheme: const .new(thumbShape: RoundSliderThumbShape(enabledThumbRadius: 13)),
  iconTheme: const .new(color: .new(0xff50606e)),
);

const paleBlue = Color(0xffeaf0f5);

// for switch icons.
final WidgetStateProperty<Icon?> thumbIcon = WidgetStateProperty.resolveWith<Icon?>((states) {
  if (states.contains(WidgetState.selected)) return const Icon(Icons.check_rounded);
  return const Icon(Icons.close_rounded);
});

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    var maxConnections = 8;
    var client = super.createHttpClient(context);
    client.maxConnectionsPerHost = maxConnections;
    return client;
  }
}

const Uuid idGenerator = Uuid();

enum SpotAlertView { alarms, map, settings }

void navigateToView(SpotAlert spotAlert, SpotAlertView view) {
  spotAlert.view = view;
  spotAlert.setState();
  spotAlert.pageController.animateToPage(view.index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  debugPrintInfo('Navigating to $view.');
}

void debugPrintMessage(String message) {
  if (kDebugMode) debugPrint(message);
}

void debugPrintInfo(String message) => debugPrintMessage('ℹ️ $message');
void debugPrintWarning(String message) => debugPrintMessage('⚠️ $message');
void debugPrintError(String message) => debugPrintMessage('❌ $message');

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: JuneBuilder(
        () => SpotAlert(),
        builder: (spotAlert) {
          return Scaffold(
            body: PageView(
              controller: spotAlert.pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe gesture to change pages
              children: [const AlarmsView(), const MapView(), const SettingsView()],
            ),
            extendBody: true,
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                boxShadow: [.new(color: Colors.black.withValues(alpha: 0.1), spreadRadius: 2, blurRadius: 5)],
                borderRadius: const .only(topLeft: .circular(50), topRight: .circular(50)),
              ),
              child: ClipRRect(
                borderRadius: const .only(topLeft: .circular(50), topRight: .circular(50)),
                child: NavigationBar(
                  onDestinationSelected: (int index) {
                    var newView = SpotAlertView.values[index];
                    navigateToView(spotAlert, newView);
                  },
                  selectedIndex: spotAlert.view.index,
                  destinations: SpotAlertView.values.map((view) {
                    var (icon, label) = switch (view) {
                      .alarms => (Icons.pin_drop_rounded, 'Alarms'),
                      .map => (Icons.map_rounded, 'Map'),
                      .settings => (Icons.settings_rounded, 'Settings'),
                    };

                    return NavigationDestination(icon: Icon(icon), label: label);
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
      theme: spotAlertTheme,
      navigatorKey: navigatorKey,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isIOS) {
    debugPrintError('This app is not supported on this platform. Supported platforms: iOS');
    await SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    return;
  }

  await SystemChrome.setPreferredOrientations([.portraitUp]);

  var permission = await Geolocator.checkPermission();
  if (permission == .denied) {
    permission = await Geolocator.requestPermission();
    if (permission == .denied) {
      return Future.error('Location permissions are denied');
    }
  }

  // Set up http overrides. This is needed to increase the number of concurrent http requests allowed. This helps with the map tiles loading.
  HttpOverrides.global = MyHttpOverrides();

  // Initialize map tile cache.
  var documentsDir = await getApplicationDocumentsDirectory();
  try {
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDir.path);
  } on Exception catch (error, stackTrace) {
    debugPrintInfo('FMTC initialization failed: $error\n$stackTrace');

    // Attempt to delete the corrupted FMTC directory.
    var fmtcDir = Directory(path.join(documentsDir.path, 'fmtc'));
    await fmtcDir.delete(recursive: true);

    // Retry FMTC initialization.
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDir.path);
  }

  runApp(const MainApp());
}
