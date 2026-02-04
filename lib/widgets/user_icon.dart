import 'package:flutter/material.dart';
import 'package:spot_alert/app.dart';

class UserIcon extends StatelessWidget {
  const UserIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.person_rounded,
      size: 30,
      color: Colors.blueAccent,
      shadows: solidOutlineShadows(color: Colors.white, radius: 2),
    );
  }
}
