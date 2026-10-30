// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/kernoid.dart';
import 'format.dart';

/// Saves a blob in the Downloads folder – or the app's documents where a system has none (iOS, Android) – and says
/// where. **OPEN**: opening it, and the system's share sheet on phones.
Future<void> saveBlob(
  BuildContext context,
  Kernoid account, {
  required String? accountId,
  required String blobId,
  required String name,
  required String mediaType,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = AppLocalizations.of(context);
  try {
    final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final path = await account.download(
      accountId: accountId,
      blobId: blobId,
      name: name,
      mediaType: mediaType,
      directory: directory.path,
    );
    messenger.showSnackBar(SnackBar(content: Text(l.savedTo(path))));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(l.error(errorText(error)))));
  }
}

/// Saves an attachment of an end-to-end encrypted message – taken from the message decrypted on this device.
Future<void> savePart(
  BuildContext context,
  Kernoid account, {
  required String emailId,
  required int part,
  required String name,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = AppLocalizations.of(context);
  try {
    final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final path = await account.savePart(emailId: emailId, partIndex: part, name: name, directory: directory.path);
    messenger.showSnackBar(SnackBar(content: Text(l.savedTo(path))));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(l.error(errorText(error)))));
  }
}
