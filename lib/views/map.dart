import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/spot_alert.dart';

class MapView extends StatelessWidget {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => SpotAlert(),
      builder: (spotAlert) {
        if (spotAlert.tileProvider == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        // If the map is locked to the user's location, disable move interaction.
        var myInteractiveFlags = InteractiveFlag.all & ~InteractiveFlag.rotate;
        if (spotAlert.followUserLocation) {
          myInteractiveFlags = myInteractiveFlags & ~InteractiveFlag.pinchMove & ~InteractiveFlag.drag & ~InteractiveFlag.flingAnimation;
        }

        return FlutterMap(
          mapController: spotAlert.mapController,
          options: MapOptions(
            keepAlive: true, // Since the app has multiple pages, we want to map widget to stay alive so we can still use MapController in other places.
            initialZoom: initialZoom,
            interactionOptions: InteractionOptions(flags: myInteractiveFlags),
            onMapReady: () => onMapReady(spotAlert),
          ),
          children: [
            TileLayer(
              urlTemplate: openStreetMapTemplateUrl,
              userAgentPackageName: spotAlert.packageInfo.packageName,
              tileProvider: spotAlert.tileProvider,
            ),
            AlarmMarkers(alarms: spotAlert.alarms, circleToMarkerZoomThreshold: circleToMarkerZoomThreshold),
            UserPosition(position: spotAlert.position),
            AlarmPlacementDisplay(isPlacingAlarm: spotAlert.isPlacingAlarm, alarmPlacementRadius: spotAlert.alarmPlacementRadius),
            Compass(alarms: spotAlert.alarms, showClosestNonVisibleAlarmSetting: spotAlert.showClosestNonVisibleAlarmSetting, userPosition: spotAlert.position),
            const Overlay(),
          ],
        );
      },
    );
  }
}

class UserPosition extends StatelessWidget {
  final LatLng? position;

  const UserPosition({required this.position, super.key});

  @override
  Widget build(BuildContext context) {
    if (position == null) return const SizedBox.shrink();

    return MarkerLayer(
      markers: [
        Marker(
          point: position!,
          child: const Icon(Icons.circle, color: Colors.blue),
        ),
        Marker(
          point: position!,
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
        ),
      ],
    );
  }
}

class AlarmMarkers extends StatelessWidget {
  final List<Alarm> alarms;
  final double circleToMarkerZoomThreshold;

  const AlarmMarkers({
    required this.alarms,
    required this.circleToMarkerZoomThreshold,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Display the alarms as circles or markers on the map. We create a set of markers or circles
    // representing the same alarms. The markers are only visible when the user is zoomed out
    // beyond (below) circleToMarkerZoomThreshold.
    var showMarkersInsteadOfCircles = MapCamera.of(context).zoom < circleToMarkerZoomThreshold;

    if (showMarkersInsteadOfCircles) {
      var alarmMarkers = alarms.map((a) => buildMarker(a)).toList();
      return MarkerLayer(markers: alarmMarkers);
    } else {
      var alarmCircles = alarms.map((a) => buildCircleMarker(a)).toList();
      return CircleLayer(circles: alarmCircles);
    }
  }

  Marker buildMarker(Alarm alarm) {
    return Marker(
      width: 100,
      height: 65,
      point: alarm.position,
      child: Stack(
        alignment: .center,
        children: [
          Icon(Icons.pin_drop_rounded, color: alarm.color, size: 30),
          Positioned(
            bottom: 0,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 100),
              padding: const .symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: paleBlue.withValues(alpha: 0.7),
                borderRadius: .circular(8),
              ),
              child: Text(
                alarm.name,
                style: const TextStyle(fontSize: 10),
                overflow: .ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  CircleMarker buildCircleMarker(Alarm alarm) {
    return CircleMarker(
      point: alarm.position,
      color: alarm.color.withValues(alpha: 0.5),
      borderColor: const Color(0xff2b2b2b),
      borderStrokeWidth: 2,
      radius: alarm.radius,
      useRadiusInMeter: true,
    );
  }
}

class AlarmPlacementDisplay extends StatelessWidget {
  final bool isPlacingAlarm;
  final double alarmPlacementRadius;

  const AlarmPlacementDisplay({required this.isPlacingAlarm, required this.alarmPlacementRadius, super.key});

  @override
  Widget build(BuildContext context) {
    if (!isPlacingAlarm) return const SizedBox.shrink();

    return CircleLayer(
      circles: [
        CircleMarker(
          point: MapCamera.of(context).center,
          radius: alarmPlacementRadius,
          color: Colors.redAccent.withValues(alpha: 0.5),
          borderColor: Colors.black,
          borderStrokeWidth: 2,
          useRadiusInMeter: true,
        ),
      ],
    );
  }
}

// Since we are using MapOptions: keepAlive = true, this function is only fired once throughout the app lifecycle.
Future<void> onMapReady(SpotAlert spotAlert) async {
  // From this point on we can now use mapController outside the map widget.
  spotAlert.mapControllerIsAttached = true;

  if (spotAlert.position == null) {
    // Sometimes the location package takes a while to start the position stream even if the location permissions are granted.
    await Future<void>.delayed(const Duration(seconds: 10));

    if (spotAlert.position == null) {
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          behavior: .floating,
          content: Container(
            padding: const .all(8),
            child: const Text('Are location permissions enabled?'),
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.location),
          ),
          shape: RoundedRectangleBorder(borderRadius: .circular(10)),
        ),
      );
    }
  }

  await moveMapToUserLocation(spotAlert);
}

void followOrUnfollowUser(SpotAlert spotAlert) {
  if (spotAlert.position == null) {
    debugPrint('Cannot follow the user since there is no position.');
    return;
  }

  spotAlert.followUserLocation = !spotAlert.followUserLocation;
  spotAlert.setState();

  // If we are following, then we need to move the map immediately instead
  // of waiting for the next location update.
  if (spotAlert.followUserLocation) moveMapToUserLocation(spotAlert);
}

Future<void> moveMapToUserLocation(SpotAlert spotAlert) async {
  if (!spotAlert.mapControllerIsAttached) {
    debugPrintError('The map controller is not attached. Cannot move to user location.');
    return;
  }

  if (spotAlert.position == null) {
    debugPrintError('No user position available. Cannot move to user location.');
    return;
  }

  final zoom = spotAlert.mapController.camera.zoom;
  spotAlert.mapController.move(spotAlert.position!, zoom);
}

class Compass extends StatelessWidget {
  final LatLng? userPosition;
  final List<Alarm> alarms;
  final bool showClosestNonVisibleAlarmSetting;

  const Compass({
    required this.userPosition,
    required this.alarms,
    required this.showClosestNonVisibleAlarmSetting,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;
    var ellipseWidth = screenSize.width * 0.8;
    var ellipseHeight = screenSize.height * 0.65;

    return IgnorePointer(
      child: Center(
        child: Stack(
          alignment: .center,
          children: [
            Builder(
              builder: (context) {
                // If the user's position is not visible, show an arrow pointing towards them.

                if (userPosition == null) return const SizedBox.shrink();

                var userIsVisible = MapCamera.of(context).visibleBounds.contains(userPosition!);
                if (userIsVisible) return const SizedBox.shrink();

                var arrowRotation = calculateAngleBetweenTwoPositions(MapCamera.of(context).center, userPosition!);
                var angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().

                return IgnorePointer(
                  child: Stack(
                    alignment: .center,
                    children: [
                      Transform.translate(
                        offset: Offset((ellipseWidth / 2) * cos(angle), (ellipseHeight / 2) * sin(angle)),
                        child: Transform.rotate(
                          angle: arrowRotation,
                          child: Transform.rotate(angle: -pi / 2, child: const Icon(Icons.arrow_forward_ios, color: Colors.blue, size: 28)),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)),
                        child: const Stack(
                          children: [Center(child: Icon(Icons.circle, color: Colors.blue)), Center(child: Icon(Icons.person, color: Colors.white, size: 18))],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Builder(
              builder: (context) {
                // If no alarms are currently visible on screen, show an arrow pointing towards the closest alarm (if there is one).

                if (userPosition == null) return const SizedBox.shrink();

                var closestAlarm = getClosest(userPosition!, alarms, (alarm) => alarm.position);
                if (closestAlarm == null) return const SizedBox.shrink();

                var closestAlarmIsVisible = MapCamera.of(context).visibleBounds.contains(closestAlarm.position);

                var showClosestNonVisibleAlarm = !closestAlarmIsVisible && showClosestNonVisibleAlarmSetting;
                if (!showClosestNonVisibleAlarm) return const SizedBox.shrink();

                var arrowRotation = calculateAngleBetweenTwoPositions(MapCamera.of(context).center, closestAlarm.position);
                var angle = (arrowRotation + 3 * pi / 2) % (2 * pi);
                var angleIs9to3 = angle > (0 * pi) && angle < (1 * pi);

                return IgnorePointer(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset((ellipseWidth / 2) * cos(angle), (ellipseHeight / 2) * sin(angle)),
                        child: Transform.rotate(
                          angle: arrowRotation,
                          child: Transform.rotate(angle: -pi / 2, child: Icon(Icons.arrow_forward_ios, color: closestAlarm.color, size: 28)),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)),
                        child: Icon(Icons.pin_drop_rounded, color: closestAlarm.color, size: 32),
                      ),
                      if (closestAlarm.name.isNotEmpty) ...[
                        Transform.translate(
                          offset: Offset((ellipseWidth / 2 - 26) * cos(angle), (ellipseHeight / 2 - 26) * sin(angle)),
                          child: Transform.translate(
                            // Move the text up or down depending on the angle to now overlap with the arrow.
                            offset: angleIs9to3 ? const Offset(0, -22) : const Offset(0, 22),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 100),
                              padding: const .symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: paleBlue.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                closestAlarm.name,
                                style: const TextStyle(fontSize: 10),
                                overflow: .ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class Overlay extends StatelessWidget {
  const Overlay({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => SpotAlert(),
      builder: (spotAlert) {
        var statusBarHeight = MediaQuery.of(context).padding.top;

        return Stack(
          alignment: .center,
          children: [
            Positioned(
              top: statusBarHeight + 5,
              child: const IgnorePointer(
                child: Align(
                  child: OpenStreetMapAttribution()
                ),
              ),
            ),
            Positioned(
              top: statusBarHeight + 10,
              right: 15,
              child: Column(
                crossAxisAlignment: .end,
                mainAxisAlignment: .spaceAround,
                children: [
                  FloatingActionButton(
                    child: const Icon(Icons.info_outline_rounded),
                    onPressed: () => showInfoDialog(context),
                  ),
                  const SizedBox(height: 10),
                  if (spotAlert.followUserLocation) ...[
                    FloatingActionButton(
                      onPressed: () => followOrUnfollowUser(spotAlert),
                      elevation: 4,
                      backgroundColor: const .fromARGB(255, 216, 255, 218),
                      child: const Icon(Icons.near_me_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () => followOrUnfollowUser(spotAlert),
                      elevation: 4,
                      child: const Icon(Icons.lock_rounded),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (spotAlert.isPlacingAlarm) ...[
                    FloatingActionButton(
                      onPressed: () {
                        var alarm = Alarm(name: 'Alarm', position: MapCamera.of(context).center, radius: spotAlert.alarmPlacementRadius);
                        addAlarm(spotAlert, alarm);

                        spotAlert.isPlacingAlarm = false;
                        spotAlert.alarmPlacementRadius = 100;
                        spotAlert.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.check),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      onPressed: () {
                        spotAlert.isPlacingAlarm = false;
                        spotAlert.alarmPlacementRadius = 100;
                        spotAlert.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.cancel_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () {
                        spotAlert.isPlacingAlarm = true;
                        spotAlert.followUserLocation = false;
                        spotAlert.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.pin_drop_rounded),
                    ),
                  ],
                ],
              ),
            ),
            if (spotAlert.isPlacingAlarm) ...[
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
                    padding: const .symmetric(horizontal: 15, vertical: 5),
                    child: Row(
                      children: [
                        const Text('Size:', style: TextStyle(fontWeight: .bold)),
                        Expanded(
                          child: Slider(
                            value: spotAlert.alarmPlacementRadius,
                            onChanged: (value) {
                              spotAlert.alarmPlacementRadius = value;
                              spotAlert.setState();
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
              ),
            ],
          ],
        );
      },
    );
  }
}

class OpenStreetMapAttribution extends StatelessWidget {
  const OpenStreetMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const .all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('© OpenStreetMap contributors'),
      ),
    );
  }
}

void showInfoDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (BuildContext context) => Dialog(
      child: Padding(
        padding: const .all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: <Widget>[
              Icon(Icons.info_outline_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 15),
              const Text(
                'Here you can place new alarms by tapping the marker button. You can also follow / unfollow your location by tapping the lock button.',
                textAlign: .center,
              ),
              const SizedBox(height: 15),
              const Text('Staying on the map view for long periods of time may drain your battery.', textAlign: .center),
              const SizedBox(height: 15),
              const Text(
                'Set location permissions to "While Using" or "Always" and enable notifications to use the app when running in background. Also make sure to disable Silent mode.',
                textAlign: .center,
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
  );
}

double calculateAngleBetweenTwoPositions(LatLng from, LatLng to) => atan2(to.longitude - from.longitude, to.latitude - from.latitude);
