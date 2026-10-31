// SPDX-License-Identifier: MIT
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The theme of the whole app. Material stays the framework underneath – navigation, text input, overlays – but none of
/// its look: no ripples, kernoid's colours, Plex, the web app's corners and lines. What `lib/ui` draws itself takes
/// its values from [KTokens]; the few Material widgets left (text fields, date and time pickers, menus, dialogs, snack
/// bars) are styled here to match.
ThemeData kernoidTheme(Brightness brightness) {
  final k = brightness == Brightness.dark ? KTokens.darkTokens : KTokens.lightTokens;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: k.accent,
    onPrimary: k.accentText,
    secondary: k.accent,
    onSecondary: k.accentText,
    error: k.error,
    onError: k.surface,
    surface: k.surface,
    onSurface: k.text,
    onSurfaceVariant: k.muted,
    outline: k.lineStrong,
    outlineVariant: k.line,
    surfaceContainerLowest: k.bg,
    surfaceContainerLow: k.panel,
    surfaceContainer: k.surface,
    surfaceContainerHigh: k.raised,
    surfaceContainerHighest: k.hover,
    primaryContainer: k.accentSoft,
    onPrimaryContainer: k.text,
    inverseSurface: k.text,
    onInverseSurface: k.bg,
  );
  final small = BorderRadius.circular(KSize.radiusSmall);
  final field = OutlineInputBorder(
    borderRadius: small,
    borderSide: BorderSide(color: k.lineStrong),
  );
  final body = KText.body(k);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [k],
    fontFamily: KFont.sans,
    scaffoldBackgroundColor: k.surface,
    canvasColor: k.surface,
    dividerColor: k.line,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: k.hover,
    focusColor: k.accentSoft,
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: KText.small(k),
      labelLarge: KText.label(k),
      labelMedium: KText.label(k).copyWith(fontSize: 13),
      labelSmall: KText.small(k).copyWith(fontSize: 12),
      titleLarge: KText.title(k),
      titleMedium: KText.heading(k),
      titleSmall: KText.heading(k).copyWith(fontSize: 14),
      headlineSmall: KText.title(k).copyWith(fontSize: 22),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: k.accent,
      selectionColor: k.accentSoft,
      selectionHandleColor: k.accent,
    ),
    iconTheme: IconThemeData(color: k.muted, size: KSize.icon),
    dividerTheme: DividerThemeData(color: k.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: k.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(borderSide: BorderSide(color: k.accent, width: 1.5)),
      errorBorder: field.copyWith(borderSide: BorderSide(color: k.error)),
      focusedErrorBorder: field.copyWith(borderSide: BorderSide(color: k.error, width: 1.5)),
      labelStyle: KText.small(k),
      floatingLabelStyle: KText.small(k).copyWith(color: k.accent),
      hintStyle: body.copyWith(color: k.faint),
      helperStyle: KText.small(k).copyWith(color: k.faint),
      errorStyle: KText.small(k).copyWith(color: k.error),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KSize.radius),
        side: BorderSide(color: k.line),
      ),
      titleTextStyle: KText.heading(k),
      contentTextStyle: body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: k.text,
      contentTextStyle: body.copyWith(color: k.bg, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: small),
      width: 420,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: k.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KSize.radius),
        side: BorderSide(color: k.line),
      ),
      textStyle: body,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(k.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: k.line)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radius))),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: k.text, borderRadius: BorderRadius.circular(6)),
      textStyle: KText.small(k).copyWith(color: k.bg, fontWeight: FontWeight.w500, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: k.panel,
      foregroundColor: k.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: KSize.bar,
      titleSpacing: 12,
      titleTextStyle: KText.heading(k).copyWith(fontSize: 17),
      iconTheme: IconThemeData(color: k.muted, size: KSize.icon),
      actionsIconTheme: IconThemeData(color: k.muted, size: KSize.icon),
      shape: Border(bottom: BorderSide(color: k.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: _button(k, k.accent, k.accentText, k.accent, FontWeight.w600)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _button(k, k.accent, k.accentText, k.accent, FontWeight.w600)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _button(k, k.raised, k.text, k.line, FontWeight.w500)),
    textButtonTheme: TextButtonThemeData(
      style: _button(k, Colors.transparent, k.accent, Colors.transparent, FontWeight.w500),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(k.muted),
        overlayColor: WidgetStatePropertyAll(k.hover),
        iconSize: const WidgetStatePropertyAll(KSize.icon),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: small)),
      ),
    ),
    cardTheme: CardThemeData(
      color: k.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KSize.radius),
        side: BorderSide(color: k.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      iconColor: k.muted,
      textColor: k.text,
      selectedColor: k.text,
      selectedTileColor: k.accentSoft,
      titleTextStyle: body.copyWith(fontWeight: FontWeight.w500),
      subtitleTextStyle: KText.small(k),
      shape: RoundedRectangleBorder(borderRadius: small),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: k.raised,
      selectedColor: k.accentSoft,
      side: BorderSide(color: k.line),
      labelStyle: KText.label(k).copyWith(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: small),
      checkmarkColor: k.accent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: small)),
        side: WidgetStatePropertyAll(BorderSide(color: k.line)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? k.accent : k.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? k.accentText : k.text,
        ),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(k.raised),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      constraints: const BoxConstraints(minHeight: KSize.control + 4),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: small)),
      side: WidgetStateProperty.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.focused) ? k.accent : k.line),
      ),
      textStyle: WidgetStatePropertyAll(body),
      hintStyle: WidgetStatePropertyAll(body.copyWith(color: k.faint)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: k.accent,
      foregroundColor: k.accentText,
      elevation: 2,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radius)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: k.accent, linearTrackColor: k.line),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.accent : null),
      checkColor: WidgetStatePropertyAll(k.accentText),
      side: BorderSide(color: k.lineStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.accentText : k.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.accent : k.raised),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.accent : k.line),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: k.panel,
      headerForegroundColor: k.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radius)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: k.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radius)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(k.lineStrong),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// Material's buttons drawn as the web app's: 36 px high, small corners, no ripple.
ButtonStyle _button(KTokens k, Color background, Color foreground, Color border, FontWeight weight) => ButtonStyle(
  backgroundColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.hovered) && background == Colors.transparent ? k.hover : background,
  ),
  foregroundColor: WidgetStatePropertyAll(foreground),
  overlayColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.hovered)
        ? (background == Colors.transparent ? Colors.transparent : Colors.white.withValues(alpha: 0.06))
        : null,
  ),
  side: WidgetStatePropertyAll(BorderSide(color: border)),
  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radiusSmall))),
  minimumSize: const WidgetStatePropertyAll(Size(0, KSize.control)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
  textStyle: WidgetStatePropertyAll(KText.label(k).copyWith(fontWeight: weight)),
  iconSize: const WidgetStatePropertyAll(16),
  elevation: const WidgetStatePropertyAll(0),
  splashFactory: NoSplash.splashFactory,
  visualDensity: VisualDensity.standard,
);
