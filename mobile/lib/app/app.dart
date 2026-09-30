import 'package:flutter/material.dart';

import 'theme.dart';

/// Racine de l'app : applique le thème et affiche l'écran reçu de `main.dart`.
class MyApp extends StatelessWidget {
  final Widget home;

  const MyApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'NoWave', theme: appTheme, home: home);
  }
}
