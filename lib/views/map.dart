import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/loca_alert.dart';
import 'package:loca_alert/main.dart';
import 'package:loca_alert/models/alarm.dart';
import 'package:location/location.dart';

class MapView extends StatelessWidget {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => LocaAlert(),
      builder: (state) {
        var mapTileCacheStoreReference = state.mapTileCacheStore;
        if (mapTileCacheStoreReference == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        var statusBarHeight = MediaQuery.of(context).padding.top;
        var screenSize = MediaQuery.of(context).size;

        var userLocationReference = state.userLocation;
        var userLocationMarker = <Marker>[];
        if (userLocationReference != null)
          userLocationMarker.addAll([
            Marker(
              point: userLocationReference,
              child: const Icon(Icons.circle, color: Colors.blue),
            ),
            Marker(
              point: userLocationReference,
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
            ),
          ]);

        // Display the alarms as circles or markers on the map. We create a set of markers or circles
        // representing the same alarms. The markers are only visible when the user is zoomed out
        // beyond (below) circleToMarkerZoomThreshold.
        var alarmCircles = <CircleMarker>[];
        var alarmMarkers = <Marker>[];
        var showMarkersInsteadOfCircles = false;
        if (state.cameraZoom != null) {
          showMarkersInsteadOfCircles = state.cameraZoom! < circleToMarkerZoomThreshold;
        }

        if (showMarkersInsteadOfCircles) {
          for (var alarm in state.alarms) {
            var marker = Marker(
              width: 100,
              height: 65,
              point: alarm.position,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.pin_drop_rounded, color: alarm.color, size: 30),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 100),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: paleBlue.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        alarm.name,
                        style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            );

            alarmMarkers.add(marker);
          }
        } else {
          for (var alarm in state.alarms) {
            var circle = CircleMarker(
              point: alarm.position,
              color: alarm.color.withValues(alpha: 0.5),
              borderColor: const Color(0xff2b2b2b),
              borderStrokeWidth: 2,
              radius: alarm.radius,
              useRadiusInMeter: true,
            );

            alarmCircles.add(circle);
          }
        }

        CircleMarker? alarmPlacementCircle;
        if (state.isPlacingAlarm) {
          var centerOfMap = state.mapController.camera.center;
          var alarmPlacementPosition = centerOfMap;
          alarmPlacementCircle = CircleMarker(
            point: alarmPlacementPosition,
            radius: state.alarmPlacementRadius,
            color: Colors.redAccent.withValues(alpha: 0.5),
            borderColor: Colors.black,
            borderStrokeWidth: 2,
            useRadiusInMeter: true,
          );
        }

        // If the map is locked to the user's location, disable move interaction.
        var myInteractiveFlags = InteractiveFlag.all & ~InteractiveFlag.rotate;
        if (state.followUserLocation) myInteractiveFlags = myInteractiveFlags & ~InteractiveFlag.pinchMove & ~InteractiveFlag.drag & ~InteractiveFlag.flingAnimation;

        return Stack(
          alignment: Alignment.center,
          children: [
            FlutterMap(
              mapController: state.mapController,
              options: MapOptions(
                initialCenter: state.initialCenter ?? const LatLng(0, 0),
                initialZoom: initialZoom,
                interactionOptions: InteractionOptions(flags: myInteractiveFlags),
                keepAlive: true,
                onMapEvent: (event) => myOnMapEvent(event, state),
                onMapReady: () => myOnMapReady(state),
              ),
              children: [
                TileLayer(
                  urlTemplate: openStreetMapTemplateUrl,
                  userAgentPackageName: state.packageInfo.packageName,
                  tileProvider: CachedTileProvider(
                    maxStale: const Duration(days: 30),
                    store: mapTileCacheStoreReference,
                  ),
                ),
                if (showMarkersInsteadOfCircles) MarkerLayer(markers: alarmMarkers) else CircleLayer(circles: alarmCircles),
                if (alarmPlacementCircle != null) CircleLayer(circles: [alarmPlacementCircle]),
                if (state.userLocation != null) MarkerLayer(markers: userLocationMarker),
                Builder(
                  builder: (context) {
                    // If no alarms are currently visible on screen, show an arrow pointing towards the closest alarm (if there is one).
                    Alarm? closestAlarm;
                    var closestAlarmIsVisible = false;
                    if (state.visibleCenter != null) {
                      closestAlarm = getClosestAlarmToPosition(state.visibleCenter!, state.alarms);

                      if (state.visibleBounds != null) {
                        closestAlarmIsVisible = state.visibleBounds!.contains(closestAlarm!.position);
                      }
                    }

                    var showClosestAlarm = closestAlarm != null && !closestAlarmIsVisible && state.showClosestOffScreenAlarmSetting;
                    if (!showClosestAlarm) return const SizedBox.shrink();

                    // TODO(james): reduce / organize
                    var ellipseWidth = screenSize.width * 0.8;
                    var ellipseHeight = screenSize.height * 0.65;
                    var indicatorColor = closestAlarm.color;
                    var arrow = Transform.rotate(angle: -pi / 2, child: Icon(Icons.arrow_forward_ios, color: indicatorColor, size: 28));
                    var indicatorAlarmIcon = Icon(Icons.pin_drop_rounded, color: indicatorColor, size: 32);
                    var arrowRotation = calculateAngleBetweenTwoPositions(MapCamera.of(context).center, closestAlarm.position);
                    var angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().
                    var angleIs9to3 = angle > (0 * pi) && angle < (1 * pi); // This is used to offset the text from the icon to not overlap with the arrow.

                    return Stack(
                      children: [
                        IgnorePointer(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset((ellipseWidth / 2) * cos(angle), (ellipseHeight / 2) * sin(angle)),
                              child: Transform.rotate(
                                angle: arrowRotation,
                                child: arrow,
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)),
                              child: indicatorAlarmIcon,
                            ),
                          ),
                        ),
                        if (closestAlarm.name.isNotEmpty)
                          IgnorePointer(
                            child: Center(
                              child: Transform.translate(
                                offset: Offset((ellipseWidth / 2 - 26) * cos(angle), (ellipseHeight / 2 - 26) * sin(angle)),
                                child: Transform.translate(
                                  // Move the text up or down depending on the angle to now overlap with the arrow.
                                  offset: angleIs9to3 ? const Offset(0, -22) : const Offset(0, 22),
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 100),
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: paleBlue.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      closestAlarm.name,
                                      style: const TextStyle(fontSize: 10),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
            // Attribution to OpenStreetMap
            Positioned(
              top: statusBarHeight + 5,
              child: IgnorePointer(
                child: Align(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '© OpenStreetMap contributors',
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: statusBarHeight + 10,
              right: 15,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  FloatingActionButton(
                    child: const Icon(Icons.info_outline_rounded),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (BuildContext context) => Dialog(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.info_outline_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(height: 15),
                                const Text(
                                  'Here you can place new alarms by tapping the marker button. You can also follow / unfollow your location by tapping the lock button.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 15),
                                const Text('Staying on the map view for long periods of time may drain your battery.', textAlign: TextAlign.center),
                                const SizedBox(height: 15),
                                const Text(
                                  'Set location permissions to "While Using" or "Always" and enable notifications to use the app when running in background.',
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (state.followUserLocation) ...[
                    FloatingActionButton(
                      onPressed: () => followOrUnfollowUserLocation(state),
                      elevation: 4,
                      backgroundColor: const Color.fromARGB(255, 216, 255, 218),
                      child: const Icon(Icons.near_me_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () => followOrUnfollowUserLocation(state),
                      elevation: 4,
                      child: const Icon(Icons.lock_rounded),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (state.isPlacingAlarm) ...[
                    FloatingActionButton(
                      onPressed: () {
                        var centerOfMap = state.mapController.camera.center;
                        var alarmPlacementPosition = centerOfMap;
                        var alarm = Alarm(name: 'Alarm', position: alarmPlacementPosition, radius: state.alarmPlacementRadius);
                        addAlarm(state, alarm);
                        resetAlarmPlacementUIState(state);
                        state.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.check),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      onPressed: () {
                        resetAlarmPlacementUIState(state);
                        state.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.cancel_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () {
                        state.isPlacingAlarm = true;
                        state.followUserLocation = false;
                        state.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.pin_drop_rounded),
                    ),
                  ],
                  const SizedBox.shrink(),
                ],
              ),
            ),
            if (state.isPlacingAlarm)
              Positioned(
                bottom: 150,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.all(Radius.circular(15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.5),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    child: Row(
                      children: [
                        const Text('Size:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Slider(
                            value: state.alarmPlacementRadius,
                            onChanged: (value) {
                              state.alarmPlacementRadius = value;
                              state.setState();
                            },
                            min: 100,
                            max: 3000,
                            divisions: 100,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
          ],
        );
      },
    );
  }

  void myOnMapEvent(MapEvent event, LocaAlert state) {
    state.visibleBounds = state.mapController.camera.visibleBounds;
    state.visibleCenter = state.mapController.camera.center;
    state.cameraZoom = state.mapController.camera.zoom;
    state.setState();
  }

  Future<void> myOnMapReady(LocaAlert state) async {
    // TODO(james): refactor. maybe use a switch?
    var initialCenterReference = state.initialCenter;
    var shouldMoveToInitialCenter = initialCenterReference != null;
    if (shouldMoveToInitialCenter) {
      state.followUserLocation = false;
      state.mapController.move(initialCenterReference, state.mapController.camera.zoom);
      state.initialCenter = null;
      state.setState();
    }

    var serviceIsEnabled = await location.serviceEnabled();
    if (!serviceIsEnabled) {
      var newIsServiceEnabled = await location.requestService();
      if (!newIsServiceEnabled) {
        debugPrintError('Location services are not enabled.');
        return;
      }
    }

    var permission = await location.hasPermission();
    debugPrintInfo('Location permission status: $permission');

    // If the user has denied location permissions forever, we can't request them, so we show a snackbar.
    if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
      debugPrintWarning('User has denied location permissions.');
      ScaffoldMessenger.of(NavigationService.navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Container(
            padding: const EdgeInsets.all(8),
            child: const Text('Location permissions are required to use this app.'),
          ),
          action: SnackBarAction(label: 'Settings', onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.location)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      return;
    }

    // The remaining case is that the user has granted location permissions, so we do nothing.
  }
}

void followOrUnfollowUserLocation(LocaAlert locaAlert) {
  if (locaAlert.followUserLocation) {
    locaAlert.followUserLocation = false;
    locaAlert.setState();
  } else {
    // Check if we actually can follow the user's location. If not, show a snackbar.
    if (locaAlert.userLocation == null) {
      debugPrintError("Unable to follow the user's location.");
      ScaffoldMessenger.of(NavigationService.navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Container(
            padding: const EdgeInsets.all(8),
            child: const Text('Unable to follow your location. Are location services permitted?'),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      locaAlert.followUserLocation = true;
      moveMapToUserLocation(locaAlert);
      locaAlert.setState();
    }
  }
}

Future<void> moveMapToUserLocation(LocaAlert locaAlert) async {
  var currentViewIsMap = locaAlert.view != LocaAlertView.map;
  if (currentViewIsMap) {
    return;
  }

  var userPosition = locaAlert.userLocation;
  var cameraZoom = locaAlert.cameraZoom;
  if (userPosition == null || cameraZoom == null) {
    debugPrintError('Unable to move map to user location.');
    return;
  }

  locaAlert.mapController.move(userPosition, cameraZoom);
  debugPrintInfo('Moving map to user location.');
}

double calculateAngleBetweenTwoPositions(LatLng from, LatLng to) => atan2(to.longitude - from.longitude, to.latitude - from.latitude);

Future<void> navigateToAlarm(LocaAlert locaAlert, Alarm alarm) async {
  locaAlert.initialCenter = alarm.position;
  navigateToView(locaAlert, LocaAlertView.map);
}
