// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'kernoid';

  @override
  String get signInTitle => 'Sign in to kernoid';

  @override
  String get server => 'Server';

  @override
  String get serverHint => 'https://kernoid.example';

  @override
  String get address => 'Address';

  @override
  String get appPassword => 'App password';

  @override
  String get appPasswordHint => 'Make one on your account page. Signing in with a passkey follows.';

  @override
  String get signIn => 'Sign in';

  @override
  String get required => 'Required';

  @override
  String get mail => 'Mail';

  @override
  String get files => 'Files';

  @override
  String get account => 'Account';

  @override
  String get inbox => 'Inbox';

  @override
  String get drafts => 'Drafts';

  @override
  String get sent => 'Sent';

  @override
  String get archive => 'Archive';

  @override
  String get junk => 'Junk';

  @override
  String get trash => 'Trash';

  @override
  String get noMessages => 'No messages';

  @override
  String get noSubject => '(no subject)';

  @override
  String get selectMessage => 'Select a message';

  @override
  String get from => 'From';

  @override
  String get to => 'To';

  @override
  String get cc => 'Cc';

  @override
  String get subject => 'Subject';

  @override
  String get message => 'Message';

  @override
  String get write => 'Write';

  @override
  String get send => 'Send';

  @override
  String get discard => 'Discard';

  @override
  String get messageSent => 'Message sent';

  @override
  String get attachments => 'Attachments';

  @override
  String get save => 'Save';

  @override
  String savedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get loadMore => 'Load more';

  @override
  String get myFiles => 'My files';

  @override
  String get folderEmpty => 'This folder is empty';

  @override
  String get refresh => 'Refresh';

  @override
  String get signedInAs => 'Signed in as';

  @override
  String get signOut => 'Sign out';

  @override
  String get e2eTitle => 'End-to-end encryption';

  @override
  String get e2eBody =>
      'Coming next: your key is made on this device and unlocked with your passkey. Mail to people with a key is encrypted without a setting, and vaults keep files only you can read.';

  @override
  String error(String message) {
    return 'Something went wrong: $message';
  }

  @override
  String get retry => 'Try again';

  @override
  String get e2eUnavailable => 'This server does not offer end-to-end encryption.';

  @override
  String get e2eNoKey =>
      'Your account has no key yet. Make one here: it is made on this device, and the server keeps it only protected – by a recovery code that only you have.';

  @override
  String get e2eMakeKey => 'Make my key';

  @override
  String get e2eLocked => 'Your key is locked. Enter your recovery code to read encrypted mail and to send encrypted.';

  @override
  String get e2eUnlocked =>
      'Unlocked on this device. Mail to people with a key goes encrypted and signed – without a setting.';

  @override
  String get recoveryCode => 'Recovery code';

  @override
  String get unlock => 'Unlock';

  @override
  String get lock => 'Lock';

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String get postQuantum => 'post-quantum (ML-KEM and ML-DSA with Curve25519)';

  @override
  String get compatibleKind => 'compatible (Curve25519)';

  @override
  String get tenantRecovers => 'Your organisation can recover your key.';

  @override
  String get recoveryTitle => 'Your recovery code';

  @override
  String get recoveryBody =>
      'Write it down or keep it in your password manager. It is shown only now. Without it – and without a passkey that unlocks your key – mail encrypted to you cannot be read again.';

  @override
  String get recoveryKept => 'I have kept the code safe';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get done => 'Done';

  @override
  String get encryptedMessage => 'Encrypted message';

  @override
  String get unlockToRead => 'Unlock your key to read it';

  @override
  String get lockedEmail => 'This message is end-to-end encrypted. Unlock your key to read it.';

  @override
  String get e2eEncrypted => 'End-to-end encrypted';

  @override
  String get signatureVerified => 'signature checked';

  @override
  String get signatureUnverified => 'signature not checked';

  @override
  String get notSigned => 'not signed';

  @override
  String get willEncrypt => 'Will be sent end-to-end encrypted and signed.';

  @override
  String wontEncrypt(String reason) {
    return 'Not end-to-end encrypted: $reason';
  }

  @override
  String get sentEncrypted => 'Sent end-to-end encrypted';

  @override
  String get cancel => 'Cancel';
}
