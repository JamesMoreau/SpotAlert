import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/dialogs/info_dialog.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/spot_alert_state.dart';

const openStreetMapTemplateUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const initialZoom = 13.0;
const circleToMarkerZoomThreshold = 10.0;

class MapView extends StatelessWidget {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      SpotAlert.new,
      builder: (spotAlert) {
        // If the map is locked to the user's location, disable move interaction.
        var myInteractiveFlags = InteractiveFlag.all & ~InteractiveFlag.rotate;
        if (spotAlert.followUser) {
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
            AlarmMarkers(alarms: spotAlert.alarms, threshold: circleToMarkerZoomThreshold),
            UserPosition(stream: spotAlert.positionStream),
            AlarmPlacementMarker(isPlacing: spotAlert.isPlacingAlarm, radius: spotAlert.alarmPlacementRadius),
            Compass(alarms: spotAlert.alarms, userPositionStream: spotAlert.positionStream),
            const Overlay(),
          ],
        );
      },
    );
  }
}

// Since we are using MapOptions: keepAlive = true, this function is only fired once throughout the app lifecycle.
Future<void> onMapReady(SpotAlert spotAlert) async {
  // From this point on we can now use mapController outside the map widget.
  spotAlert.mapIsReady.complete();

  final messenger = globalScaffoldKey.currentState;

  // Check and request location permissions.
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    showLocationUnavailableSnackbar(messenger);
    return;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == .denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == .denied || permission == .deniedForever) {
    debugPrintWarning('Location permissions are denied');
    showLocationUnavailableSnackbar(messenger);
    return;
  }

  // From this point assume location permissions are granted.

  var position = await Geolocator.getLastKnownPosition();
  if (position != null) {
    final latlng = LatLng(position.latitude, position.longitude);
    tryMoveMap(spotAlert, latlng);

    return;
  }

  // Sometimes the location package takes a while to start the position stream even if the location permissions are granted.
  await Future<void>.delayed(const Duration(seconds: 10));

  // Try again to get location
  position = await Geolocator.getLastKnownPosition();
  if (position != null) {
    final latlng = LatLng(position.latitude, position.longitude);
    tryMoveMap(spotAlert, latlng);

    return;
  }

  showLocationUnavailableSnackbar(messenger);
}

void showLocationUnavailableSnackbar(ScaffoldMessengerState? messenger) {
  if (messenger == null) {
    debugPrintError('Could not show snackbar because scaffold messenger was null');
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      behavior: .floating,
      content: const Padding(padding: .all(8), child: Text('Are location permissions enabled?')),
      action: .new(
        label: 'Settings',
        onPressed: () => AppSettings.openAppSettings(type: .location),
      ),
      shape: RoundedRectangleBorder(borderRadius: .circular(10)),
    ),
  );
}

class UserPosition extends StatelessWidget {
  final Stream<LatLng> stream;

  const UserPosition({required this.stream, super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        final position = snapshot.data;

        if (position == null) return const SizedBox.shrink();

        return MarkerLayer(
          markers: [
            .new(
              point: position,
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
  final double threshold;

  const AlarmMarkers({required this.alarms, required this.threshold, super.key});

  @override
  Widget build(BuildContext context) {
    // Display the alarms as circles or markers on the map. We create a set of markers or circles
    // representing the same alarms. The markers are only visible when the user is zoomed out
    // beyond (below) circleToMarkerZoomThreshold.
    final showMarkersInsteadOfCircles = MapCamera.of(context).zoom < threshold;

    if (showMarkersInsteadOfCircles) {
      final alarmMarkers = alarms.map(buildMarker).toList();
      return MarkerLayer(markers: alarmMarkers);
    } else {
      final alarmCircles = alarms.map(buildCircleMarker).toList();
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
  final bool isPlacing;
  final double radius;

  const AlarmPlacementMarker({required this.isPlacing, required this.radius, super.key});

  @override
  Widget build(BuildContext context) {
    if (!isPlacing) return const SizedBox.shrink();

    return CircleLayer(
      circles: [
        .new(
          point: MapCamera.of(context).center,
          radius: radius,
          color: Colors.redAccent.withValues(alpha: 0.5),
          borderColor: Colors.black,
          borderStrokeWidth: 2,
          useRadiusInMeter: true,
        ),
      ],
    );
  }
}

class Compass extends StatelessWidget {
  final Stream<LatLng> userPositionStream;
  final List<Alarm> alarms;

  const Compass({required this.userPositionStream, required this.alarms, super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final ellipseWidth = screenSize.width * 0.8;
    final ellipseHeight = screenSize.height * 0.65;

    return StreamBuilder(
      stream: userPositionStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        final position = snapshot.data;

        // Nothing to show for compass if user position not available
        if (position == null) return const SizedBox.shrink();

        final camera = MapCamera.of(context);

        // If the user's position exists but is not visible, show an arrow pointing towards them.
        Widget? userArrow;
        final userIsVisible = camera.visibleBounds.contains(position);
        if (!userIsVisible) {
          final arrowRotation = calculateAngleBetweenTwoPositions(camera.center, position);
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
        final closestAlarm = getClosest(position, alarms, (alarm) => alarm.position);
        if (closestAlarm != null) {
          final closestAlarmIsVisible = !camera.visibleBounds.contains(closestAlarm.position);
          if (closestAlarmIsVisible) {
            final arrowRotation = calculateAngleBetweenTwoPositions(MapCamera.of(context).center, closestAlarm.position);
            final angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().

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

T? getClosest<T>(LatLng target, List<T> items, LatLng Function(T) getPosition) {
  T? closestItem;
  var closestDistance = double.infinity;

  for (final item in items) {
    final itemPositon = getPosition(item);
    final d = const Distance().distance(itemPositon, target);
    if (d < closestDistance) {
      closestDistance = d;
      closestItem = item;
    }
  }

  return closestItem;
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

double calculateAngleBetweenTwoPositions(LatLng from, LatLng to) => atan2(to.longitude - from.longitude, to.latitude - from.latitude);

class Overlay extends StatelessWidget {
  const Overlay({super.key});

  Future<void> placeAlarm(SpotAlert spotAlert, LatLng position) async {
    final alarm = Alarm(name: 'Alarm', position: position, radius: spotAlert.alarmPlacementRadius);
    spotAlert.alarms.add(alarm);

    // We allow the user to have more alarms than amount of allowed geofences. The alarm will just remain unactive.
    final result = await activateAlarm(alarm);
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

    await saveAlarmsToStorage(spotAlert);
  }

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      SpotAlert.new,
      builder: (spotAlert) {
        final statusBarHeight = MediaQuery.of(context).padding.top;

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
                  FloatingActionButton(
                    child: const Icon(Icons.info_outline_rounded),
                    onPressed: () => showDialog<void>(context: context, builder: (context) => const InfoDialog()),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton(
                    onPressed: () async {
                      final success = await followOrUnfollowUser(spotAlert);
                      if (success) spotAlert.setState();
                    },
                    elevation: 4,
                    backgroundColor: spotAlert.followUser ? const Color.fromARGB(255, 216, 255, 218) : null,
                    child: Icon(spotAlert.followUser ? Icons.near_me_rounded : Icons.lock_rounded),
                  ),
                  const SizedBox(height: 10),
                  if (spotAlert.isPlacingAlarm) ...[
                    FloatingActionButton(onPressed: () => placeAlarm(spotAlert, MapCamera.of(context).center), elevation: 4, child: const Icon(Icons.check)),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      onPressed: () {
                        spotAlert
                          ..isPlacingAlarm = false
                          ..alarmPlacementRadius = initialAlarmRadius
                          ..setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.cancel_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () {
                        spotAlert
                          ..isPlacingAlarm = true
                          ..followUser = false
                          ..setState();
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
                              spotAlert
                                ..alarmPlacementRadius = value
                                ..setState();
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
