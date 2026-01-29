import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/spot_alert.dart';

const openStreetMapTemplateUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const initialZoom = 13.0;
const circleToMarkerZoomThreshold = 10.0;

class MapView extends StatelessWidget {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => SpotAlert(),
      builder: (spotAlert) {
        // If the map is locked to the user's location, disable move interaction.
        var myInteractiveFlags = InteractiveFlag.all & ~InteractiveFlag.rotate;
        if (spotAlert.followUserLocation) {
          myInteractiveFlags = myInteractiveFlags & ~InteractiveFlag.pinchMove & ~InteractiveFlag.drag & ~InteractiveFlag.flingAnimation;
        }

        return FlutterMap(
          mapController: spotAlert.mapController,
          options: .new(
            keepAlive: true, // Since the app has multiple pages, we want to map widget to stay alive so we can still use MapController in other places.
            initialZoom: initialZoom,
            interactionOptions: .new(flags: myInteractiveFlags),
            onMapReady: () => onMapReady(spotAlert),
          ),
          children: [
            TileLayer(urlTemplate: openStreetMapTemplateUrl, userAgentPackageName: spotAlert.packageInfo.packageName, tileProvider: spotAlert.tileProvider),
            AlarmMarkers(alarms: spotAlert.alarms, circleToMarkerZoomThreshold: circleToMarkerZoomThreshold),
            UserPosition(positionStream: spotAlert.positionStream),
            AlarmPlacementMarker(isPlacingAlarm: spotAlert.isPlacingAlarm, alarmPlacementRadius: spotAlert.alarmPlacementRadius),
            Compass(alarms: spotAlert.alarms, userPositionStream: spotAlert.positionStream),
            const Overlay(),
          ],
        );
      },
    );
  }
}

class UserPosition extends StatelessWidget {
  final Stream<Position> positionStream;

  const UserPosition({required this.positionStream, super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: positionStream,
      builder: (context, snapshot) {
        var position = snapshot.data;

        if (position == null) {
          return const SizedBox.shrink();
        }

        var latlng = LatLng(position.latitude, position.longitude);

        return MarkerLayer(
          markers: [
            .new(
              point: latlng,
              child: Icon(
                Icons.person_rounded,
                color: Colors.blue,
                size: 30,
                shadows: solidOutlineShadows(color: Colors.white, radius: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AlarmMarkers extends StatelessWidget {
  final List<Alarm> alarms;
  final double circleToMarkerZoomThreshold;

  const AlarmMarkers({required this.alarms, required this.circleToMarkerZoomThreshold, super.key});

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
          Icon(
            Icons.pin_drop_rounded,
            color: alarm.color,
            size: 30,
            shadows: solidOutlineShadows(color: Colors.white, radius: 2),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              constraints: const .new(maxWidth: 100),
              padding: const .symmetric(horizontal: 2),
              decoration: BoxDecoration(color: paleBlue.withValues(alpha: 0.7), borderRadius: .circular(8)),
              child: Text(alarm.name, style: const .new(fontSize: 10), overflow: .ellipsis, maxLines: 1),
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
      borderColor: Colors.white,
      borderStrokeWidth: 2,
      radius: alarm.radius,
      useRadiusInMeter: true,
    );
  }
}

class AlarmPlacementMarker extends StatelessWidget {
  final bool isPlacingAlarm;
  final double alarmPlacementRadius;

  const AlarmPlacementMarker({required this.isPlacingAlarm, required this.alarmPlacementRadius, super.key});

  @override
  Widget build(BuildContext context) {
    if (!isPlacingAlarm) return const SizedBox.shrink();

    return CircleLayer(
      circles: [
        .new(
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
        .new(
          behavior: .floating,
          content: Container(padding: const .all(8), child: const Text('Are location permissions enabled?')),
          action: .new(
            label: 'Settings',
            onPressed: () => AppSettings.openAppSettings(type: .location),
          ),
          shape: RoundedRectangleBorder(borderRadius: .circular(10)),
        ),
      );
    }
  }

  moveMapToUserLocation(spotAlert);
}

void followOrUnfollowUser(SpotAlert spotAlert) {
  if (spotAlert.position == null) {
    debugPrintInfo('Cannot follow the user since there is no position.');
    return;
  }

  spotAlert.followUserLocation = !spotAlert.followUserLocation;
  spotAlert.setState();

  // If we are following, then we need to move the map immediately instead
  // of waiting for the next location update.
  if (spotAlert.followUserLocation) moveMapToUserLocation(spotAlert);
}

void moveMapToUserLocation(SpotAlert spotAlert) {
  if (!spotAlert.mapControllerIsAttached) {
    debugPrintError('The map controller is not attached. Cannot move to user location.');
    return;
  }

  if (spotAlert.position == null) {
    debugPrintError('No user position available. Cannot move to user location.');
    return;
  }

  var zoom = spotAlert.mapController.camera.zoom;
  spotAlert.mapController.move(spotAlert.position!, zoom);
}

class Compass extends StatelessWidget {
  final Stream<Position> userPositionStream;
  final List<Alarm> alarms;

  const Compass({required this.userPositionStream, required this.alarms, super.key});

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;
    var ellipseWidth = screenSize.width * 0.8;
    var ellipseHeight = screenSize.height * 0.65;

    return StreamBuilder(
      stream: userPositionStream,
      builder: (context, snapshot) {
        var position = snapshot.data;

        // Nothing to show for compass if user position not available
        if (position == null) return const SizedBox.shrink();
        var latlng = LatLng(position.latitude, position.longitude);

        var camera = MapCamera.of(context);

        // If the user's position exists but is not visible, show an arrow pointing towards them.
        Widget? userArrow;
        var userIsVisible = camera.visibleBounds.contains(latlng);
        if (!userIsVisible) {
          final arrowRotation = calculateAngleBetweenTwoPositions(camera.center, latlng);
          final angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().

          userArrow = CompassArrow(
            angle: angle,
            arrowRotation: arrowRotation,
            ellipseWidth: ellipseWidth,
            ellipseHeight: ellipseHeight,
            color: Colors.blue,
            targetIcon: Icons.person,
          );
        }

        // If no alarms are currently visible on screen, show an arrow pointing towards the closest alarm (if there is one).
        Widget? alarmArrow;
        var closestAlarm = getClosest(latlng, alarms, (alarm) => alarm.position);
        if (closestAlarm != null) {
          var closestAlarmIsVisible = !camera.visibleBounds.contains(closestAlarm.position);
          if (closestAlarmIsVisible) {
            var arrowRotation = calculateAngleBetweenTwoPositions(MapCamera.of(context).center, closestAlarm.position);
            var angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().

            alarmArrow = CompassArrow(
              angle: angle,
              arrowRotation: arrowRotation,
              ellipseWidth: ellipseWidth,
              ellipseHeight: ellipseHeight,
              color: closestAlarm.color,
              targetIcon: Icons.pin_drop_rounded,
              label: closestAlarm.name,
            );
          }
        }

        return IgnorePointer(
          child: Center(
            child: Stack(alignment: .center, children: [if (userArrow != null) userArrow, if (alarmArrow != null) alarmArrow]),
          ),
        );
      },
    );
  }
}

class CompassArrow extends StatelessWidget {
  final double angle;
  final double arrowRotation;
  final double ellipseWidth;
  final double ellipseHeight;

  final Color color;
  final IconData targetIcon;
  final String? label;

  const CompassArrow({
    required this.angle,
    required this.arrowRotation,
    required this.ellipseWidth,
    required this.ellipseHeight,
    required this.color,
    required this.targetIcon,
    this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final angleIs9to3 = angle > 0 && angle < pi;

    return IgnorePointer(
      child: Stack(
        alignment: .center,
        children: [
          Transform.translate(
            offset: .new((ellipseWidth / 2) * cos(angle), (ellipseHeight / 2) * sin(angle)),
            child: Transform.rotate(
              angle: arrowRotation,
              child: Transform.rotate(
                angle: -pi / 2,
                child: Icon(Icons.arrow_forward_ios, color: color, size: 28),
              ),
            ),
          ),
          Transform.translate(
            offset: .new((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)),
            child: Icon(
              targetIcon,
              size: 32,
              color: color,
              shadows: solidOutlineShadows(color: Colors.white, radius: 2),
            ),
          ),
          if (label != null) ...[
            Transform.translate(
              offset: .new((ellipseWidth / 2 - 26) * cos(angle), (ellipseHeight / 2 - 26) * sin(angle)),
              child: Transform.translate(
                // Move the text up or down depending on the angle to now overlap with the arrow.
                offset: .new(0, angleIs9to3 ? -22 : 22),
                child: Container(
                  constraints: const .new(maxWidth: 100),
                  padding: const .symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: paleBlue.withValues(alpha: 0.7), borderRadius: .circular(8)),
                  child: Text(label!, style: const .new(fontSize: 10), overflow: .ellipsis, maxLines: 1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class Overlay extends StatelessWidget {
  const Overlay({super.key});

  Future<void> placeAlarm(SpotAlert spotAlert, LatLng position) async {
    var alarm = Alarm(name: 'Alarm', position: position, radius: spotAlert.alarmPlacementRadius);
    spotAlert.alarms.add(alarm);

    // We allow the user to have more alarms than amount of allowed geofences. The alarm will just remain unactive.
    var result = await activateAlarm(alarm);
    switch (result) {
      case ActivateAlarmResult.success:
        spotAlert.isPlacingAlarm = false;
        spotAlert.alarmPlacementRadius = initialAlarmRadius;
        spotAlert.setState();
      case ActivateAlarmResult.limitReached:
        debugPrintWarning('Newly placed alarm could not be activated due to the limit on the number of geofences.');
      case ActivateAlarmResult.failed:
        debugPrintError('Could not activate newly placed alarm.');
    }

    await saveSpotAlertAlarms(spotAlert);
  }

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
              child: const IgnorePointer(child: Align(child: OpenStreetMapAttribution())),
            ),
            Positioned(
              top: statusBarHeight + 10,
              right: 15,
              child: Column(
                crossAxisAlignment: .end,
                mainAxisAlignment: .spaceAround,
                children: [
                  FloatingActionButton(child: const Icon(Icons.info_outline_rounded), onPressed: () => showInfoDialog(context)),
                  const SizedBox(height: 10),
                  if (spotAlert.followUserLocation) ...[
                    FloatingActionButton(
                      onPressed: () => followOrUnfollowUser(spotAlert),
                      elevation: 4,
                      backgroundColor: const .fromARGB(255, 216, 255, 218),
                      child: const Icon(Icons.near_me_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(onPressed: () => followOrUnfollowUser(spotAlert), elevation: 4, child: const Icon(Icons.lock_rounded)),
                  ],
                  const SizedBox(height: 10),
                  if (spotAlert.isPlacingAlarm) ...[
                    FloatingActionButton(onPressed: () => placeAlarm(spotAlert, MapCamera.of(context).center), elevation: 4, child: const Icon(Icons.check)),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      onPressed: () {
                        spotAlert.isPlacingAlarm = false;
                        spotAlert.alarmPlacementRadius = initialAlarmRadius;
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
                    borderRadius: const .all(.circular(15)),
                    boxShadow: [.new(color: Colors.grey.withValues(alpha: 0.5), spreadRadius: 2, blurRadius: 5, offset: const Offset(0, 3))],
                  ),
                  child: Padding(
                    padding: const .symmetric(horizontal: 15, vertical: 5),
                    child: Row(
                      children: [
                        const Text('Size:', style: .new(fontWeight: .bold)),
                        Expanded(
                          child: Slider(
                            value: spotAlert.alarmPlacementRadius,
                            onChanged: (value) {
                              spotAlert.alarmPlacementRadius = value;
                              spotAlert.setState();
                            },
                            min: minimumAlarmRadius,
                            max: maximumAlarmRadius,
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
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), borderRadius: .circular(8)),
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
            children: [
              Icon(Icons.info_outline_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 15),
              const Text(
                'Here you can place new alarms by tapping the marker button. You can also follow / unfollow your location by tapping the lock button.',
                textAlign: .center,
              ),
              const SizedBox(height: 15),
              const Text('Staying on the map view for long periods of time may drain your battery.', textAlign: .center),
              const SizedBox(height: 15),
              const Text('Set location permissions to "While Using" or "Always" and enable notifications to use the app when running in background.', textAlign: .center),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        ),
      ),
    ),
  );
}

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

double calculateAngleBetweenTwoPositions(LatLng from, LatLng to) => atan2(to.longitude - from.longitude, to.latitude - from.latitude);
