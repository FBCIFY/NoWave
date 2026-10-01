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

/// Thème Material par défaut (boutons, champs, barre du haut).
///
/// Les écrans sombres d'authentification et de profil ont leur propre style :
/// voir `AuthLayout`.
final appTheme = ThemeData(
  useMaterial3: true,
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
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
);
