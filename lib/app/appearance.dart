// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Light, dark or as the system is – kept on this device in the app's support directory, not at the server.
abstract final class Appearance {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/appearance');

  static Future<void> load() async {
    try {
      final name = (await (await _file()).readAsString()).trim();
      mode.value = ThemeMode.values.firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
    } catch (_) {
      // Nothing kept yet: as the system is.
    }
  }

  static Future<void> set(ThemeMode value) async {
    mode.value = value;
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(value.name);
    } catch (_) {
      // Not kept: the choice holds until the app ends.
    }
  }
}
