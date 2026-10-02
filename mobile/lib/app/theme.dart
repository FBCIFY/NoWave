import 'package:flutter/material.dart';

/// Couleurs de la charte NoWave, réutilisées directement dans les écrans.
abstract final class AppColors {
  static const slate900 = Color(0xFF0F172A);
  static const blue950 = Color(0xFF172554);
  static const cyan500 = Color(0xFF06B6D4);
  static const blue600 = Color(0xFF2563EB);

  static const background = Color(0xFFF5F7FC);
  static const text = Color(0xFF0F172A);
}

const _fontFamily = 'Raleway';

/// Chiffres alignés : par défaut, Raleway dessine des chiffres de hauteurs
/// inégales, peu lisibles dans les coordonnées, distances et compteurs.
const _liningFigures = TextStyle(fontFeatures: [FontFeature.liningFigures()]);

const _liningFiguresTheme = TextTheme(
  displayLarge: _liningFigures,
  displayMedium: _liningFigures,
  displaySmall: _liningFigures,
  headlineLarge: _liningFigures,
  headlineMedium: _liningFigures,
  headlineSmall: _liningFigures,
  titleLarge: _liningFigures,
  titleMedium: _liningFigures,
  titleSmall: _liningFigures,
  bodyLarge: _liningFigures,
  bodyMedium: _liningFigures,
  bodySmall: _liningFigures,
  labelLarge: _liningFigures,
  labelMedium: _liningFigures,
  labelSmall: _liningFigures,
);

/// Thème Material par défaut (police, boutons, champs, barre du haut).
///
/// Les écrans sombres d'authentification et de profil ont leur propre style :
/// voir `AuthLayout`.
final appTheme = ThemeData(
  useMaterial3: true,
  fontFamily: _fontFamily,
  textTheme: _liningFiguresTheme,
  primaryTextTheme: _liningFiguresTheme,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.blue600,
    primary: AppColors.blue600,
    secondary: AppColors.cyan500,
  ),
  scaffoldBackgroundColor: AppColors.background,
  appBarTheme: const AppBarTheme(
    centerTitle: true,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    foregroundColor: AppColors.text,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD7E3EC)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.cyan500, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      // Ce style remplace celui du thème au lieu de le compléter : la police
      // et les chiffres alignés doivent être repris ici.
      textStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.liningFigures()],
      ),
    ),
  ),
);
