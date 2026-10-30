// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

/// kernoid's colours (kernoid/brand): Night, Mint – violet only in the glitch of the mark, never in the interface.
abstract final class KernoidColors {
  static const night = Color(0xFF0B0D10);
  static const mint = Color(0xFF3DDC97);
  static const mintDark = Color(0xFF0F7F52);
  static const glitchWhite = Color(0xFFD8FFFF);
}

ThemeData kernoidTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: KernoidColors.mint, brightness: brightness);
  scheme = scheme.copyWith(
    primary: dark ? KernoidColors.mint : KernoidColors.mintDark,
    onPrimary: dark ? KernoidColors.night : Colors.white,
    surface: dark ? KernoidColors.night : null,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    listTileTheme: const ListTileThemeData(dense: true),
  );
}
