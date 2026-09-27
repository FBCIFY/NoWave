import 'package:flutter/material.dart';

import 'theme.dart';

class MyApp extends StatelessWidget {
  final Widget home;

  const MyApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'NoWave', theme: appTheme, home: home);
  }
}
