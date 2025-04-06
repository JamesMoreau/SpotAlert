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
      builder: (locaAlert) {
        if (locaAlert.mapTileCacheStore == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        var statusBarHeight = MediaQuery.of(context).padding.top;

        // If the map is locked to the user's location, disable move interaction.
        var myInteractiveFlags = InteractiveFlag.all & ~InteractiveFlag.rotate;
        if (locaAlert.followUserLocation) myInteractiveFlags = myInteractiveFlags & ~InteractiveFlag.pinchMove & ~InteractiveFlag.drag & ~InteractiveFlag.flingAnimation;

        return Stack(
          alignment: Alignment.center,
          children: [
            FlutterMap(
              mapController: locaAlert.mapController,
              options: MapOptions(
                keepAlive: true,
                initialZoom: initialZoom,
                interactionOptions: InteractionOptions(flags: myInteractiveFlags),
                onMapReady: () => myOnMapReady(locaAlert),
              ),
              children: [
                TileLayer(
                  urlTemplate: openStreetMapTemplateUrl,
                  userAgentPackageName: locaAlert.packageInfo.packageName,
                  tileProvider: CachedTileProvider(
                    maxStale: const Duration(days: 30),
                    store: locaAlert.mapTileCacheStore!,
                  ),
                ),
                Builder(
                  builder: (context) {
                    // Display the alarms as circles or markers on the map. We create a set of markers or circles
                    // representing the same alarms. The markers are only visible when the user is zoomed out
                    // beyond (below) circleToMarkerZoomThreshold.
                    var showMarkersInsteadOfCircles = MapCamera.of(context).zoom < circleToMarkerZoomThreshold;
                    if (showMarkersInsteadOfCircles) {
                      var alarmMarkers = <Marker>[];

                      for (var alarm in locaAlert.alarms) {
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

                      return MarkerLayer(markers: alarmMarkers);
                    } else {
                      var alarmCircles = <CircleMarker>[];

                      for (var alarm in locaAlert.alarms) {
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

                      return CircleLayer(circles: alarmCircles);
                    }
                  },
                ),
                StreamBuilder(
                  stream: locaAlert.location.onLocationChanged,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      debugPrintError('Error getting location: ${snapshot.error}');
                      return const SizedBox.shrink();
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }

                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    var locationData = snapshot.data!;
                    if (locationData.latitude == null || locationData.longitude == null) {
                      debugPrintError('Location data is null: $locationData');
                      return const SizedBox.shrink();
                    }

                    var location = LatLng(locationData.latitude!, locationData.longitude!);

                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: location,
                          child: const Icon(Icons.circle, color: Colors.blue),
                        ),
                        Marker(
                          point: location,
                          child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
                        ),
                      ],
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    if (!locaAlert.isPlacingAlarm) return const SizedBox.shrink();

                    return CircleLayer(
                      circles: [
                        CircleMarker(
                          point: MapCamera.of(context).center,
                          radius: locaAlert.alarmPlacementRadius,
                          color: Colors.redAccent.withValues(alpha: 0.5),
                          borderColor: Colors.black,
                          borderStrokeWidth: 2,
                          useRadiusInMeter: true,
                        ),
                      ],
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    // If no alarms are currently visible on screen, show an arrow pointing towards the closest alarm (if there is one).
                    var closestAlarmIsVisible = false;
                    var closestAlarm = getClosest(MapCamera.of(context).center, locaAlert.alarms, (alarm) => alarm.position);
                    if (closestAlarm != null) {
                      closestAlarmIsVisible = MapCamera.of(context).visibleBounds.contains(closestAlarm.position);
                    }

                    var showClosestNonVisibleAlarm = closestAlarm != null && !closestAlarmIsVisible && locaAlert.showClosestNonVisibleAlarmSetting;
                    if (!showClosestNonVisibleAlarm) return const SizedBox.shrink();

                    var screenSize = MediaQuery.of(context).size;
                    var ellipseWidth = screenSize.width * 0.8;
                    var ellipseHeight = screenSize.height * 0.65;
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
                                child: Transform.rotate(angle: -pi / 2, child: Icon(Icons.arrow_forward_ios, color: closestAlarm.color, size: 28)),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)),
                              child: Icon(Icons.pin_drop_rounded, color: closestAlarm.color, size: 32),
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
                    child: const Text('© OpenStreetMap contributors'),
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
                                  onPressed: () => Navigator.pop(context),
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
                  if (locaAlert.followUserLocation) ...[
                    FloatingActionButton(
                      onPressed: () => followOrUnfollowUser(locaAlert),
                      elevation: 4,
                      backgroundColor: const Color.fromARGB(255, 216, 255, 218),
                      child: const Icon(Icons.near_me_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () => followOrUnfollowUser(locaAlert),
                      elevation: 4,
                      child: const Icon(Icons.lock_rounded),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (locaAlert.isPlacingAlarm) ...[
                    FloatingActionButton(
                      onPressed: () {
                        var alarm = Alarm(name: 'Alarm', position: locaAlert.mapController.camera.center, radius: locaAlert.alarmPlacementRadius);
                        addAlarm(locaAlert, alarm);

                        locaAlert.isPlacingAlarm = false;
                        locaAlert.alarmPlacementRadius = 100;
                        locaAlert.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.check),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      onPressed: () {
                        locaAlert.isPlacingAlarm = false;
                        locaAlert.alarmPlacementRadius = 100;
                        locaAlert.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.cancel_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () {
                        locaAlert.isPlacingAlarm = true;
                        locaAlert.followUserLocation = false;
                        locaAlert.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.pin_drop_rounded),
                    ),
                  ],
                  const SizedBox.shrink(),
                ],
              ),
            ),
            if (locaAlert.isPlacingAlarm)
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
                            value: locaAlert.alarmPlacementRadius,
                            onChanged: (value) {
                              locaAlert.alarmPlacementRadius = value;
                              locaAlert.setState();
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

  Future<void> myOnMapReady(LocaAlert locaAlert) async {
    locaAlert.mapControllerIsAttached = true;

    var serviceIsEnabled = await locaAlert.location.serviceEnabled();
    if (!serviceIsEnabled) {
      var newIsServiceEnabled = await locaAlert.location.requestService();
      if (!newIsServiceEnabled) {
        debugPrintError('Location services are not enabled.');
        return;
      }
    }

    var permission = await locaAlert.location.hasPermission();
    debugPrintInfo('Location permission status: $permission');

    // If the user has denied location permissions forever, we can't request them, so we show a snackbar.
    if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
      debugPrintWarning('User has denied location permissions.');
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
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

void followOrUnfollowUser(LocaAlert locaAlert) {
  locaAlert.followUserLocation = !locaAlert.followUserLocation;
  locaAlert.setState();
  
  // If we are following, then we need to move the map immediately instead 
  // of waiting for the next location update.
  if (locaAlert.followUserLocation) moveMapToUserLocation(locaAlert);
}

Future<void> moveMapToUserLocation(LocaAlert locaAlert) async {
  var locationData = await locaAlert.location.getLocation();
  if (locationData.latitude == null || locationData.longitude == null) {
    debugPrintError('Cannot determine the user location.');
    return;
  }

  if (!locaAlert.mapControllerIsAttached) {
    debugPrintError('The map controller is not attached. Cannot move to user location.');
    return;
  }

  final location = LatLng(locationData.latitude!, locationData.longitude!);
  final zoom = locaAlert.mapController.camera.zoom;
  locaAlert.mapController.move(location, zoom);
}

double calculateAngleBetweenTwoPositions(LatLng from, LatLng to) => atan2(to.longitude - from.longitude, to.latitude - from.latitude);
