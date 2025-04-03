import 'dart:async';
import 'dart:io';

import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/loca_alert.dart';
import 'package:loca_alert/views/alarms.dart';
import 'package:loca_alert/views/map.dart';
import 'package:loca_alert/views/settings.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/*
TODO:
  Should opening map view immedietly move to user (when not locked on)?
  Check that we are actually saving the settings to file. Also have default value if failed to load.
  would be cool to have user's position off screen indicator as well.
*/

const author = 'James Moreau';
const myEmail = 'jp.moreau@aol.com';
const githubLink = 'www.github.com/jamesmoreau';
const appleID = '6478944468';

const openStreetMapTemplateUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const mapTileCacheFilename = 'myMapTiles';
const settingsAlarmVibrationKey = 'alarmVibration';
const settingsAlarmNotificationKey = 'alarmNotification';
const settingsShowClosestNonVisibleAlarmKey = 'showClosestNonVisibleAlarm';
const settingsFilename = 'settings.json';
const alarmsFilename = 'alarms.json';

const initialZoom = 15.0;
const circleToMarkerZoomThreshold = 10.0;
const maxZoomSupported = 18.0;
const alarmCheckPeriod = Duration(seconds: 5);
const locationPermissionCheckInterval = Duration(seconds: 20);
const numberOfTriggeredAlarmVibrations = 6;

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
    brightness: Brightness.light,
    primary: Color(0xff006493),
    onPrimary: Colors.white,
    primaryContainer: Color.fromARGB(255, 216, 237, 255),
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
    contentPadding: const EdgeInsets.all(25),
    tileColor: const Color.fromARGB(255, 234, 239, 246), // Background color of the ListTile
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  sliderTheme: const SliderThemeData(
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 13),
  ),
  iconTheme: const IconThemeData(color: Color(0xff50606e)),
);

const paleBlue = Color(0xffeaf0f5);

// for switch icons.
final WidgetStateProperty<Icon?> thumbIcon = WidgetStateProperty.resolveWith<Icon?>((states) {
  if (states.contains(WidgetState.selected)) return const Icon(Icons.check_rounded);
  return const Icon(Icons.close_rounded);
});

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
int id = 0;

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyHttpOverrides extends HttpOverrides {
  final int maxConnections = 8;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    var client = super.createHttpClient(context);
    client.maxConnectionsPerHost = maxConnections;
    return client;
  }
}

Location location = Location();

const Uuid idGenerator = Uuid();

enum LocaAlertView { alarms, map, settings }

void navigateToView(LocaAlert locaAlert, LocaAlertView view) {
  locaAlert.view = view;
  locaAlert.setState();
  locaAlert.pageController.animateToPage(view.index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

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
        () => LocaAlert(),
        builder: (locaAlert) {
          // Check that everything is initialized before building the app. Right now, the only thing that needs to be initialized is the map tile cache.
          var appIsInitialized = locaAlert.mapTileCacheStore != null;
          if (!appIsInitialized) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          return Scaffold(
            body: PageView(
              controller: locaAlert.pageController,
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
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    spreadRadius: 2,
                    blurRadius: 5,
                  ),
                ],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(50),
                  topRight: Radius.circular(50),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(50),
                  topRight: Radius.circular(50),
                ),
                child: NavigationBar(
                  elevation: 3,
                  onDestinationSelected: (int index) {
                    var newView = LocaAlertView.values[index];
                    navigateToView(locaAlert, newView);
                  },
                  selectedIndex: locaAlert.view.index,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.pin_drop_rounded),
                      label: 'Alarms',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.map_rounded),
                      label: 'Map',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_rounded),
                      label: 'Settings',
                    ),
                  ],
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
  if (!(Platform.isIOS || Platform.isAndroid)) {
    debugPrintError('This app is not supported on this platform. Supported platforms are iOS and Android.');
    await SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    return;
  }

  runApp(const MainApp());

  var locaAlert = June.getState(() => LocaAlert());

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  var initializationSettings = const InitializationSettings(iOS: DarwinInitializationSettings());
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await location.enableBackgroundMode();
  location.onLocationChanged.listen((location) async {
    if (location.latitude == null || location.longitude == null) return;

    locaAlert.userLocation = LatLng(location.latitude!, location.longitude!);
    locaAlert.setState();

    await checkAlarms(locaAlert);

    var shouldMoveMapToUserLocation = locaAlert.followUserLocation && locaAlert.view == LocaAlertView.map;
    if (shouldMoveMapToUserLocation) await moveMapToUserLocation(locaAlert);
  });

  // Check periodically if the location permission has been denied. If so, cancel the location updates.
  Timer.periodic(locationPermissionCheckInterval, (timer) async {
    var permission = await location.hasPermission();

    if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
      locaAlert.userLocation = null;
      locaAlert.followUserLocation = false;
      locaAlert.setState();
    }
  });

  await loadSettings(locaAlert);
  await loadAlarmsFromStorage(locaAlert);

  // Set up http overrides. This is needed to increase the number of concurrent http requests allowed. This helps with the map tiles loading.
  HttpOverrides.global = MyHttpOverrides();

  var cacheDirectory = await getApplicationCacheDirectory();
  var mapTileCachePath = '${cacheDirectory.path}${Platform.pathSeparator}$mapTileCacheFilename';
  locaAlert.mapTileCacheStore = FileCacheStore(mapTileCachePath);
  locaAlert.setState(); // Notify the ui that the map tile cache is loaded.
}
