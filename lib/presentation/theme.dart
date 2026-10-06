import 'package:flutter/material.dart';

/// Material 3, dark + light (spec V1).
class LookoutTheme {
  static const _seed = Color(0xFF2E6BE6);

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: _seed, brightness: Brightness.light),
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
      );
}
