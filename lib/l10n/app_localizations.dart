import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('de'), Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'kernoid'**
  String get appTitle;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to kernoid'**
  String get signInTitle;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @serverHint.
  ///
  /// In en, this message translates to:
  /// **'https://kernoid.example'**
  String get serverHint;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @appPassword.
  ///
  /// In en, this message translates to:
  /// **'App password'**
  String get appPassword;

  /// No description provided for @appPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Make one on your account page. Signing in with a passkey follows.'**
  String get appPasswordHint;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @mail.
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get mail;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// No description provided for @drafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get drafts;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @junk.
  ///
  /// In en, this message translates to:
  /// **'Junk'**
  String get junk;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages'**
  String get noMessages;

  /// No description provided for @noSubject.
  ///
  /// In en, this message translates to:
  /// **'(no subject)'**
  String get noSubject;

  /// No description provided for @selectMessage.
  ///
  /// In en, this message translates to:
  /// **'Select a message'**
  String get selectMessage;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @cc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get cc;

  /// No description provided for @subject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get subject;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @write.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get write;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @messageSent.
  ///
  /// In en, this message translates to:
  /// **'Message sent'**
  String get messageSent;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @savedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String savedTo(String path);

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @myFiles.
  ///
  /// In en, this message translates to:
  /// **'My files'**
  String get myFiles;

  /// No description provided for @folderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get folderEmpty;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as'**
  String get signedInAs;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @e2eTitle.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encryption'**
  String get e2eTitle;

  /// No description provided for @e2eBody.
  ///
  /// In en, this message translates to:
  /// **'Coming next: your key is made on this device and unlocked with your passkey. Mail to people with a key is encrypted without a setting, and vaults keep files only you can read.'**
  String get e2eBody;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {message}'**
  String error(String message);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @e2eUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server does not offer end-to-end encryption.'**
  String get e2eUnavailable;

  /// No description provided for @e2eNoKey.
  ///
  /// In en, this message translates to:
  /// **'Your account has no key yet. Make one here: it is made on this device, and the server keeps it only protected – by a recovery code that only you have.'**
  String get e2eNoKey;

  /// No description provided for @e2eMakeKey.
  ///
  /// In en, this message translates to:
  /// **'Make my key'**
  String get e2eMakeKey;

  /// No description provided for @e2eLocked.
  ///
  /// In en, this message translates to:
  /// **'Your key is locked. Enter your recovery code to read encrypted mail and to send encrypted.'**
  String get e2eLocked;

  /// No description provided for @e2eUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked on this device. Mail to people with a key goes encrypted and signed – without a setting.'**
  String get e2eUnlocked;

  /// No description provided for @recoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCode;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @lock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lock;

  /// No description provided for @fingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get fingerprint;

  /// No description provided for @postQuantum.
  ///
  /// In en, this message translates to:
  /// **'post-quantum (ML-KEM and ML-DSA with Curve25519)'**
  String get postQuantum;

  /// No description provided for @compatibleKind.
  ///
  /// In en, this message translates to:
  /// **'compatible (Curve25519)'**
  String get compatibleKind;

  /// No description provided for @tenantRecovers.
  ///
  /// In en, this message translates to:
  /// **'Your organisation can recover your key.'**
  String get tenantRecovers;

  /// No description provided for @recoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Your recovery code'**
  String get recoveryTitle;

  /// No description provided for @recoveryBody.
  ///
  /// In en, this message translates to:
  /// **'Write it down or keep it in your password manager. It is shown only now. Without it – and without a passkey that unlocks your key – mail encrypted to you cannot be read again.'**
  String get recoveryBody;

  /// No description provided for @recoveryKept.
  ///
  /// In en, this message translates to:
  /// **'I have kept the code safe'**
  String get recoveryKept;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @encryptedMessage.
  ///
  /// In en, this message translates to:
  /// **'Encrypted message'**
  String get encryptedMessage;

  /// No description provided for @unlockToRead.
  ///
  /// In en, this message translates to:
  /// **'Unlock your key to read it'**
  String get unlockToRead;

  /// No description provided for @lockedEmail.
  ///
  /// In en, this message translates to:
  /// **'This message is end-to-end encrypted. Unlock your key to read it.'**
  String get lockedEmail;

  /// No description provided for @e2eEncrypted.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get e2eEncrypted;

  /// No description provided for @signatureVerified.
  ///
  /// In en, this message translates to:
  /// **'signature checked'**
  String get signatureVerified;

  /// No description provided for @signatureUnverified.
  ///
  /// In en, this message translates to:
  /// **'signature not checked'**
  String get signatureUnverified;

  /// No description provided for @notSigned.
  ///
  /// In en, this message translates to:
  /// **'not signed'**
  String get notSigned;

  /// No description provided for @willEncrypt.
  ///
  /// In en, this message translates to:
  /// **'Will be sent end-to-end encrypted and signed.'**
  String get willEncrypt;

  /// No description provided for @wontEncrypt.
  ///
  /// In en, this message translates to:
  /// **'Not end-to-end encrypted: {reason}'**
  String wontEncrypt(String reason);

  /// No description provided for @sentEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Sent end-to-end encrypted'**
  String get sentEncrypted;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
