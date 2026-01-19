import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:spot_alert/spot_alert.dart';
import 'package:spot_alert/views/alarms.dart';
import 'package:spot_alert/views/map.dart';
import 'package:spot_alert/views/settings.dart';
import 'package:uuid/uuid.dart';

/*
TODO: 
  - make sure settings file not found is ok.
  - just remove settings altogether.
  - Update screenshots in app store and readme.
*/

const author = 'James Moreau';
const kofi = 'https://ko-fi.com/jamesmoreau';
const appStoreUrl = 'https://apps.apple.com/app/id6478944468';
const openStreetMapTemplateUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const mapTileStoreName = 'mapStore';
const alarmsFilename = 'alarms.json';

const initialZoom = 15.0;
const circleToMarkerZoomThreshold = 10.0;
const maxZoomSupported = 18.0;

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

ThemeData locationAlarmTheme = ThemeData(
  colorScheme: const ColorScheme(
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
  listTileTheme: ListTileThemeData(
    contentPadding: const .all(25),
    tileColor: const .fromARGB(255, 234, 239, 246), // Background color of the ListTile
    shape: RoundedRectangleBorder(
      borderRadius: .circular(8),
    ),
  ),
  sliderTheme: const SliderThemeData(
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 13),
  ),
  iconTheme: const IconThemeData(color: .new(0xff50606e)),
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

Location location = Location();

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
          // Check that everything is initialized before building the app. Right now, the only thing that needs to be initialized is the map tile cache.
          var appIsInitialized = spotAlert.tileProvider != null;
          if (!appIsInitialized) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          return Scaffold(
            body: PageView(
              controller: spotAlert.pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe gesture to change pages
              children: [
                const AlarmsView(),
                const MapView(),
                const SettingsView(),
              ],
            ),
            extendBody: true,
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  .new(
                    color: Colors.black.withValues(alpha: 0.1),
                    spreadRadius: 2,
                    blurRadius: 5,
                  ),
                ],
                borderRadius: const .only(
                  topLeft: .circular(50),
                  topRight: .circular(50),
                ),
              ),
              child: ClipRRect(
                borderRadius: const .only(
                  topLeft: .circular(50),
                  topRight: .circular(50),
                ),
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
      theme: locationAlarmTheme,
      navigatorKey: navigatorKey,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!(Platform.isIOS || Platform.isAndroid)) {
    debugPrintError('This app is not supported on this platform. Supported platforms are iOS and Android.');
    await SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    return;
  }

  var spotAlert = June.getState(() => SpotAlert());

  await SystemChrome.setPreferredOrientations([.portraitUp]);

  await Alarm.init();

  var success = await location.enableBackgroundMode();
  if (!success) {
    debugPrintWarning("Failed to initialize the location package's background mode");
  }

  location.onLocationChanged.listen(
    (location) async {
      if (location.latitude != null && location.longitude != null) {
        spotAlert.position = LatLng(location.latitude!, location.longitude!);
        spotAlert.setState();
      } else {
        debugPrintError('Location unable to be determined.');
      }

      await checkAlarms(spotAlert);

      if (spotAlert.followUserLocation) await moveMapToUserLocation(spotAlert);
    },
    onError: (error) async {
      spotAlert.position = null;
      spotAlert.followUserLocation = false;
      spotAlert.setState();
    },
  );

  await loadAlarms(spotAlert);

  // Set up http overrides. This is needed to increase the number of concurrent http requests allowed. This helps with the map tiles loading.
  HttpOverrides.global = MyHttpOverrides();

  // Initialize map tile cache.
  var documentsDirectory = (await getApplicationDocumentsDirectory()).path;
  try {
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDirectory);
  } on Exception catch (error, stackTrace) {
    debugPrint('FMTC initialization failed: $error\n$stackTrace');

    // Attempt to delete the corrupted FMTC directory.
    var dir = Directory(path.join((await getApplicationDocumentsDirectory()).absolute.path, 'fmtc'));
    await dir.delete(recursive: true);

    // Retry FMTC initialization.
    await FMTCObjectBoxBackend().initialise(rootDirectory: documentsDirectory);
  }

  await const FMTCStore(mapTileStoreName).manage.create();
  spotAlert.tileProvider = FMTCTileProvider(stores: const {mapTileStoreName: .readUpdateCreate});

  runApp(const MainApp());
}
