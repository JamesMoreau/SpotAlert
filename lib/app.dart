import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:spot_alert/main.dart';
import 'package:spot_alert/spot_alert_state.dart';
import 'package:spot_alert/views/alarms.dart';
import 'package:spot_alert/views/map.dart';
import 'package:spot_alert/views/settings.dart';

GlobalKey<ScaffoldMessengerState> globalScaffoldKey = .new();
GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

class App extends StatelessWidget {
  const App({super.key});

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
                boxShadow: [.new(color: Colors.black.withValues(alpha: .1), spreadRadius: 2, blurRadius: 5)],
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

const paleBlue = Color(0xffeaf0f5);

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
