import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_polywidget/flutter_map_polywidget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:spot_alert/app.dart';
import 'package:spot_alert/dialogs/info.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/models/alarm.dart';
import 'package:spot_alert/spot_alert_state.dart';
import 'package:spot_alert/widgets/alarm_circle_marker.dart';
import 'package:spot_alert/widgets/alarm_pin.dart';
import 'package:spot_alert/widgets/compass.dart';
import 'package:spot_alert/widgets/osm_attribution.dart';
import 'package:spot_alert/widgets/user_icon.dart';

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
            const Scalebar(alignment: .bottomLeft, padding: .only(left: 20, bottom: 150)),
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
          markers: [.new(point: position, child: const UserIcon())],
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
      final alarmCircles = alarms.map((a) => buildCircleMarker(context, a)).toList();
      return PolyWidgetLayer(polyWidgets: alarmCircles);
    }
  }

  Marker buildMarker(Alarm alarm) {
    return Marker(
      width: 100, //TODO what is the point.
      height: 65,
      point: alarm.position,
      child: Stack(
        alignment: .center,
        children: [
          AlarmPin(alarm),
          Positioned(
            bottom: 0,
            child: Container(
              constraints: const .new(maxWidth: 100),
              padding: const .symmetric(horizontal: 2),
              decoration: BoxDecoration(color: paleBlue.withValues(alpha: .7), borderRadius: .circular(8)),
              child: Text(alarm.name, style: const .new(fontSize: 10), overflow: .ellipsis, maxLines: 1),
            ),
          ),
        ],
      ),
    );
  }

  PolyWidget buildCircleMarker(BuildContext context, Alarm alarm) {
    final diameter = alarm.radius * 2;
    return PolyWidget(
      center: alarm.position,
      widthInMeters: diameter,
      heightInMeters: diameter,
      child: AlarmCircle(alarm: alarm),
    );
  }
}

// TODO: should this take isPlacing or conditionaly be included in the widget tree.
// This SHOULD use the new alarm circle widget.
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
          color: AlarmColor.redAccent.value.withValues(alpha: .5),
          borderColor: Colors.black,
          borderStrokeWidth: 2,
          useRadiusInMeter: true,
        ),
      ],
    );
  }
}

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
                spacing: 15,
                crossAxisAlignment: .end,
                mainAxisAlignment: .spaceAround,
                children: [
                  FloatingActionButton(
                    child: const Icon(Icons.info_outline_rounded),
                    onPressed: () => showDialog<void>(context: context, builder: (context) => const InfoDialog()),
                  ),
                  FloatingActionButton(
                    onPressed: () async {
                      final success = await followOrUnfollowUser(spotAlert);
                      if (success) spotAlert.setState();
                    },
                    backgroundColor: spotAlert.followUser ? const Color.fromARGB(255, 216, 255, 218) : null,
                    child: Icon(spotAlert.followUser ? Icons.near_me_rounded : Icons.lock_rounded),
                  ),
                  if (spotAlert.isPlacingAlarm) ...[
                    FloatingActionButton(onPressed: () => placeAlarm(spotAlert, MapCamera.of(context).center), child: const Icon(Icons.check)),
                    FloatingActionButton(
                      onPressed: () {
                        spotAlert
                          ..isPlacingAlarm = false
                          ..alarmPlacementRadius = initialAlarmRadius
                          ..setState();
                      },
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
                  width: MediaQuery.of(context).size.width * .9,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: const .all(.circular(15)),
                    boxShadow: [.new(color: Colors.black.withValues(alpha: .1), spreadRadius: 2, blurRadius: 5)],
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
