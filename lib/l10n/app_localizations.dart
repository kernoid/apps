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
  /// **'Make one on your account page.'**
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

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @earlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get earlier;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @allDay.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get allDay;

  /// No description provided for @noEvents.
  ///
  /// In en, this message translates to:
  /// **'No events in these two weeks'**
  String get noEvents;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get location;

  /// No description provided for @participants.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get participants;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @maybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get maybe;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @recurring.
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get recurring;

  /// No description provided for @yourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get yourAnswer;

  /// No description provided for @statusAccepted.
  ///
  /// In en, this message translates to:
  /// **'accepted'**
  String get statusAccepted;

  /// No description provided for @statusTentative.
  ///
  /// In en, this message translates to:
  /// **'maybe'**
  String get statusTentative;

  /// No description provided for @statusDeclined.
  ///
  /// In en, this message translates to:
  /// **'declined'**
  String get statusDeclined;

  /// No description provided for @statusNeedsAction.
  ///
  /// In en, this message translates to:
  /// **'no answer yet'**
  String get statusNeedsAction;

  /// No description provided for @answerSent.
  ///
  /// In en, this message translates to:
  /// **'Answer sent to the organizer'**
  String get answerSent;

  /// No description provided for @searchContacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get searchContacts;

  /// No description provided for @noContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts'**
  String get noContacts;

  /// No description provided for @emails.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emails;

  /// No description provided for @phones.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phones;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @writeEmail.
  ///
  /// In en, this message translates to:
  /// **'Write email'**
  String get writeEmail;

  /// No description provided for @organization.
  ///
  /// In en, this message translates to:
  /// **'Organisation'**
  String get organization;

  /// No description provided for @sharedBy.
  ///
  /// In en, this message translates to:
  /// **'shared by {name}'**
  String sharedBy(String name);

  /// No description provided for @newEvent.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get newEvent;

  /// No description provided for @editEvent.
  ///
  /// In en, this message translates to:
  /// **'Change event'**
  String get editEvent;

  /// No description provided for @deleteEvent.
  ///
  /// In en, this message translates to:
  /// **'Delete event'**
  String get deleteEvent;

  /// No description provided for @deleteEventConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this event? Everyone invited hears of it.'**
  String get deleteEventConfirm;

  /// No description provided for @deleteRecurringConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this event with all its repetitions? Everyone invited hears of it.'**
  String get deleteRecurringConfirm;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @starts.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get starts;

  /// No description provided for @ends.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get ends;

  /// No description provided for @calendarField.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarField;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @inviteHint.
  ///
  /// In en, this message translates to:
  /// **'Addresses, separated by commas – they get an invitation by email'**
  String get inviteHint;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get repeat;

  /// No description provided for @repeatNone.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get repeatNone;

  /// No description provided for @repeatDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get repeatDaily;

  /// No description provided for @repeatWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get repeatWeekly;

  /// No description provided for @repeatMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get repeatMonthly;

  /// No description provided for @repeatYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get repeatYearly;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get edit;

  /// No description provided for @endBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'The end is before the start'**
  String get endBeforeStart;

  /// No description provided for @recurringEditsAll.
  ///
  /// In en, this message translates to:
  /// **'Changes apply to every repetition.'**
  String get recurringEditsAll;

  /// No description provided for @newContact.
  ///
  /// In en, this message translates to:
  /// **'New contact'**
  String get newContact;

  /// No description provided for @editContact.
  ///
  /// In en, this message translates to:
  /// **'Change contact'**
  String get editContact;

  /// No description provided for @deleteContactConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this contact?'**
  String get deleteContactConfirm;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @emailsField.
  ///
  /// In en, this message translates to:
  /// **'Email addresses'**
  String get emailsField;

  /// No description provided for @phonesField.
  ///
  /// In en, this message translates to:
  /// **'Phone numbers'**
  String get phonesField;

  /// No description provided for @onePerLine.
  ///
  /// In en, this message translates to:
  /// **'One per line'**
  String get onePerLine;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @signInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Sign in with kernoid'**
  String get signInBrowser;

  /// No description provided for @signInBrowserHint.
  ///
  /// In en, this message translates to:
  /// **'In your browser – with a passkey, a password or a second factor, as your organisation has it.'**
  String get signInBrowserHint;

  /// No description provided for @orAppPassword.
  ///
  /// In en, this message translates to:
  /// **'or with an app password'**
  String get orAppPassword;

  /// No description provided for @signInAppPassword.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the app password'**
  String get signInAppPassword;

  /// No description provided for @signInCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in cancelled'**
  String get signInCancelled;

  /// No description provided for @bcc.
  ///
  /// In en, this message translates to:
  /// **'Bcc'**
  String get bcc;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyAll.
  ///
  /// In en, this message translates to:
  /// **'Reply all'**
  String get replyAll;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
  String get attachFile;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Above a quoted reply; {date} and {who} are filled in by the app, not by Flutter.
  ///
  /// In en, this message translates to:
  /// **'On {date}, {who} wrote:'**
  String quoteWrote(String date, String who);

  /// No description provided for @quoteForwarded.
  ///
  /// In en, this message translates to:
  /// **'---------- Forwarded message ----------'**
  String get quoteForwarded;

  /// How the date above a quote is written: a format of Rust's chrono (strftime).
  ///
  /// In en, this message translates to:
  /// **'%a, %d %b %Y %H:%M'**
  String get quoteDateFormat;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @thisEvent.
  ///
  /// In en, this message translates to:
  /// **'This event'**
  String get thisEvent;

  /// No description provided for @wholeSeries.
  ///
  /// In en, this message translates to:
  /// **'The whole series'**
  String get wholeSeries;

  /// No description provided for @changeWhich.
  ///
  /// In en, this message translates to:
  /// **'Change only this event or the whole series?'**
  String get changeWhich;

  /// No description provided for @deleteWhich.
  ///
  /// In en, this message translates to:
  /// **'Delete only this event or the whole series? Everyone invited hears of it.'**
  String get deleteWhich;

  /// No description provided for @editThisEvent.
  ///
  /// In en, this message translates to:
  /// **'Change this event'**
  String get editThisEvent;

  /// No description provided for @instanceEditsOne.
  ///
  /// In en, this message translates to:
  /// **'Only this event of the series changes; who is invited stays as in the series.'**
  String get instanceEditsOne;

  /// No description provided for @monthView.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get monthView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get listView;

  /// No description provided for @labelWork.
  ///
  /// In en, this message translates to:
  /// **'work'**
  String get labelWork;

  /// No description provided for @labelPrivate.
  ///
  /// In en, this message translates to:
  /// **'private'**
  String get labelPrivate;

  /// No description provided for @labelMobile.
  ///
  /// In en, this message translates to:
  /// **'mobile'**
  String get labelMobile;

  /// No description provided for @labelVoice.
  ///
  /// In en, this message translates to:
  /// **'voice'**
  String get labelVoice;

  /// No description provided for @labelText.
  ///
  /// In en, this message translates to:
  /// **'text'**
  String get labelText;

  /// No description provided for @labelVideo.
  ///
  /// In en, this message translates to:
  /// **'video'**
  String get labelVideo;

  /// No description provided for @labelFax.
  ///
  /// In en, this message translates to:
  /// **'fax'**
  String get labelFax;

  /// No description provided for @labelPager.
  ///
  /// In en, this message translates to:
  /// **'pager'**
  String get labelPager;

  /// No description provided for @labelTextphone.
  ///
  /// In en, this message translates to:
  /// **'textphone'**
  String get labelTextphone;

  /// No description provided for @labels.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get labels;

  /// No description provided for @addEmail.
  ///
  /// In en, this message translates to:
  /// **'Add an address'**
  String get addEmail;

  /// No description provided for @addPhone.
  ///
  /// In en, this message translates to:
  /// **'Add a number'**
  String get addPhone;

  /// No description provided for @loadImages.
  ///
  /// In en, this message translates to:
  /// **'Load images'**
  String get loadImages;

  /// No description provided for @imagesBlocked.
  ///
  /// In en, this message translates to:
  /// **'Images from the internet are not loaded until you ask for them.'**
  String get imagesBlocked;

  /// No description provided for @openLink.
  ///
  /// In en, this message translates to:
  /// **'Open this link?'**
  String get openLink;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @asText.
  ///
  /// In en, this message translates to:
  /// **'As text'**
  String get asText;

  /// No description provided for @asHtml.
  ///
  /// In en, this message translates to:
  /// **'Formatted'**
  String get asHtml;
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
