import 'dart:async';
import 'dart:io';

import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/constants.dart';
import 'package:loca_alert/loca_alert.dart';
import 'package:loca_alert/views/alarms.dart';
import 'package:loca_alert/views/map.dart';
import 'package:loca_alert/views/settings.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';

/*
TODO:
 try an get rid of package info state variables.
*/

void main() async {
  if (!(Platform.isIOS || Platform.isAndroid)) {
    debugPrintError('This app is not supported on this platform. Supported platforms are iOS and Android.');
    return;
  }

  runApp(const MainApp());

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  var locaAlert = June.getState(() => LocaAlert());

  var initializationSettings = const InitializationSettings(iOS: DarwinInitializationSettings());
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await location.enableBackgroundMode();
  location.onLocationChanged.listen((location) async {
    if (location.latitude == null || location.longitude == null) return;

    var state = June.getState(() => LocaAlert());
    state.userLocation = LatLng(location.latitude!, location.longitude!);
    state.setState();

    await checkAlarms();

    var shouldMoveMapToUserLocation = state.followUserLocation && state.currentView == ProximityAlarmViews.map;
    if (shouldMoveMapToUserLocation) await moveMapToUserLocation();
  });

  // Check periodically if the location permission has been denied. If so, cancel the location updates.
  var locationPermissionCheckInterval = const Duration(seconds: 20);
  Timer.periodic(locationPermissionCheckInterval, (timer) async {
    var locaAlert = June.getState(() => LocaAlert());
    var permission = await location.hasPermission();

    if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
      locaAlert.userLocation = null;
      locaAlert.followUserLocation = false;
      locaAlert.setState();
    }
  });

  await loadSettingsFromStorage(locaAlert);
  await loadAlarmsFromStorage(locaAlert);

  // Set up http overrides. This is needed to increase the number of concurrent http requests allowed. This helps with the map tiles loading.
  HttpOverrides.global = MyHttpOverrides();

  var cacheDirectory = await getApplicationCacheDirectory();
  var mapTileCachePath = '${cacheDirectory.path}${Platform.pathSeparator}$mapTileCacheFilename';
  locaAlert.mapTileCacheStore = FileCacheStore(mapTileCachePath);
  locaAlert.setState(); // Notify the ui that the map tile cache is loaded.
}

enum ProximityAlarmViews { alarms, map, settings }

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: JuneBuilder(
        () => LocaAlert(),
        builder: (state) {
          // Check that everything is initialized before building the app. Right now, the only thing that needs to be initialized is the map tile cache.
          var appIsInitialized = state.mapTileCacheStore != null;
          if (!appIsInitialized) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          return Scaffold(
            body: PageView(
              controller: state.pageController,
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
                    var newView = ProximityAlarmViews.values[index];
                    navigateToView(state, newView);
                  },
                  selectedIndex: state.currentView.index,
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
      navigatorKey: NavigationService.navigatorKey,
    );
  }
}

void navigateToView(LocaAlert locaAlert, ProximityAlarmViews view) {
  locaAlert.currentView = view;
  locaAlert.pageController.jumpToPage(view.index);
  locaAlert.setState();
  
  debugPrintInfo('Navigating to $view.');
}
