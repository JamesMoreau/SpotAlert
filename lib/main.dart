import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:june/june.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/spot_alert_state.dart';
import 'package:spot_alert/views/alarms.dart';
import 'package:spot_alert/views/map.dart';
import 'package:spot_alert/views/settings.dart';
import 'package:uuid/uuid.dart';

/*
TODO: 
  - ask for notification permissions (at startup?). how about when they add sample alarms AND on map ready.
  - KNOWN ISSUE: iOS: After reboot, the first geofence event is triggered twice, one immediatly after the other. We recommend checking the last trigger time of a geofence in your app to discard duplicates.
  - add something cute to the app like a cartoon animal or something.
  - Update screenshots in app store and readme.
  - update description in appstore to inlude train / bus.
  - startup screen icon.
*/

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

List<Shadow> solidOutlineShadows({required Color color, int radius = 1}) {
  final offsets = <Offset>[
    .new(radius.toDouble(), 0),
    .new(-radius.toDouble(), 0),
    .new(0, radius.toDouble()),
    .new(0, -radius.toDouble()),
    .new(radius.toDouble(), radius.toDouble()),
    .new(-radius.toDouble(), -radius.toDouble()),
    .new(radius.toDouble(), -radius.toDouble()),
    .new(-radius.toDouble(), radius.toDouble()),
  ];

  return offsets.map((o) => Shadow(color: color, offset: o)).toList();
}

const paleBlue = Color(0xffeaf0f5);

GlobalKey<ScaffoldMessengerState> globalScaffoldKey = .new();
GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void showMySnackBar(String message) {
  final messenger = globalScaffoldKey.currentState;
  if (messenger == null) {
    debugPrintError('Could not show snackbar because scaffold messenger is null');
    return;
  }

  messenger.showSnackBar(
    .new(
      behavior: .floating,
      content: Padding(padding: const .all(8), child: Text(message)),
      shape: RoundedRectangleBorder(borderRadius: .circular(10)),
      duration: const .new(seconds: 3),
    ),
  );
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    const maxConnections = 8;
    final client = super.createHttpClient(context)..maxConnectionsPerHost = maxConnections;
    return client;
  }
}

const Uuid idGenerator = Uuid();

enum SpotAlertView {
  alarms(icon: Icons.pin_drop_rounded, label: 'Alarms', page: AlarmsView()),
  map(icon: Icons.map_rounded, label: 'Map', page: MapView()),
  settings(icon: Icons.settings_rounded, label: 'Settings', page: SettingsView());

  const SpotAlertView({required this.icon, required this.label, required this.page});

  final IconData icon;
  final String label;
  final Widget page;
}

Future<void> navigateToView(SpotAlert spotAlert, SpotAlertView view) async {
  if (spotAlert.view == view) return;

  spotAlert
    ..view = view
    ..setState();
  await spotAlert.pageController.animateToPage(view.index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

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
        SpotAlert.new,
        builder: (spotAlert) {
          return Scaffold(
            body: PageView(
              controller: spotAlert.pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe gesture to change pages
              children: SpotAlertView.values.map((v) => v.page).toList(),
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
                    final newView = SpotAlertView.values[index];
                    navigateToView(spotAlert, newView);
                  },
                  selectedIndex: spotAlert.view.index,
                  destinations: SpotAlertView.values.map((view) => NavigationDestination(icon: Icon(view.icon), label: view.label)).toList(),
                ),
              ),
            ),
          );
        },
      ),
      theme: spotAlertTheme,
      scaffoldMessengerKey: globalScaffoldKey,
      navigatorKey: globalNavigatorKey,
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

  runApp(const MainApp());
}
