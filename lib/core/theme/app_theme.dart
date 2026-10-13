import 'package:flutter/material.dart';

/// Brand palette: orange, white and near-black.
class AppColors {
  const AppColors._();

  static const orange = Color(0xFFF47721);
  static const white = Color(0xFFFFFFFF);
  static const nearBlack = Color(0xFF171717);

  /// "Contabilizada" status: green that reads well on both themes.
  static const successContainerLight = Color(0xFFD7F2DF);
  static const onSuccessContainerLight = Color(0xFF14532D);
  static const successContainerDark = Color(0xFF1E4D2E);
  static const onSuccessContainerDark = Color(0xFFB6EBC6);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.orange,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.orange,
          onPrimary: AppColors.white,
          surface: AppColors.white,
          onSurface: AppColors.nearBlack,
        ),
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.orange,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.orange,
          onPrimary: AppColors.white,
          surface: AppColors.nearBlack,
          onSurface: AppColors.white,
        ),
      );

  static ThemeData _build(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      );
}
