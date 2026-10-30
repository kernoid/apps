// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'kernoid';

  @override
  String get signInTitle => 'Bei kernoid anmelden';

  @override
  String get server => 'Server';

  @override
  String get serverHint => 'https://kernoid.example';

  @override
  String get address => 'Adresse';

  @override
  String get appPassword => 'App-Passwort';

  @override
  String get appPasswordHint => 'Lege eines auf deiner Kontoseite an. Anmelden mit Passkey folgt.';

  @override
  String get signIn => 'Anmelden';

  @override
  String get required => 'Pflichtfeld';

  @override
  String get mail => 'Mail';

  @override
  String get files => 'Dateien';

  @override
  String get account => 'Konto';

  @override
  String get inbox => 'Posteingang';

  @override
  String get drafts => 'Entwürfe';

  @override
  String get sent => 'Gesendet';

  @override
  String get archive => 'Archiv';

  @override
  String get junk => 'Spam';

  @override
  String get trash => 'Papierkorb';

  @override
  String get noMessages => 'Keine Nachrichten';

  @override
  String get noSubject => '(kein Betreff)';

  @override
  String get selectMessage => 'Wähle eine Nachricht';

  @override
  String get from => 'Von';

  @override
  String get to => 'An';

  @override
  String get cc => 'Cc';

  @override
  String get subject => 'Betreff';

  @override
  String get message => 'Nachricht';

  @override
  String get write => 'Schreiben';

  @override
  String get send => 'Senden';

  @override
  String get discard => 'Verwerfen';

  @override
  String get messageSent => 'Nachricht gesendet';

  @override
  String get attachments => 'Anhänge';

  @override
  String get save => 'Speichern';

  @override
  String savedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get loadMore => 'Mehr laden';

  @override
  String get myFiles => 'Meine Dateien';

  @override
  String get folderEmpty => 'Dieser Ordner ist leer';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get signedInAs => 'Angemeldet als';

  @override
  String get signOut => 'Abmelden';

  @override
  String get e2eTitle => 'Ende-zu-Ende-Verschlüsselung';

  @override
  String get e2eBody =>
      'Kommt als Nächstes: Dein Schlüssel entsteht auf diesem Gerät und wird mit deinem Passkey entsperrt. Mail an Menschen mit Schlüssel wird ohne Einstellung verschlüsselt, und Tresore halten Dateien, die nur du lesen kannst.';

  @override
  String error(String message) {
    return 'Etwas ist schiefgegangen: $message';
  }

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get e2eUnavailable => 'Dieser Server bietet keine Ende-zu-Ende-Verschlüsselung.';

  @override
  String get e2eNoKey =>
      'Dein Konto hat noch keinen Schlüssel. Lege ihn hier an: Er entsteht auf diesem Gerät, und der Server bewahrt ihn nur geschützt auf – mit einem Wiederherstellungscode, den nur du hast.';

  @override
  String get e2eMakeKey => 'Schlüssel anlegen';

  @override
  String get e2eLocked =>
      'Dein Schlüssel ist gesperrt. Gib deinen Wiederherstellungscode ein, um verschlüsselte Mail zu lesen und verschlüsselt zu senden.';

  @override
  String get e2eUnlocked =>
      'Auf diesem Gerät entsperrt. Mail an Menschen mit Schlüssel geht verschlüsselt und signiert – ohne Einstellung.';

  @override
  String get recoveryCode => 'Wiederherstellungscode';

  @override
  String get unlock => 'Entsperren';

  @override
  String get lock => 'Sperren';

  @override
  String get fingerprint => 'Fingerabdruck';

  @override
  String get postQuantum => 'Post-Quanten (ML-KEM und ML-DSA mit Curve25519)';

  @override
  String get compatibleKind => 'kompatibel (Curve25519)';

  @override
  String get tenantRecovers => 'Deine Organisation kann deinen Schlüssel wiederherstellen.';

  @override
  String get recoveryTitle => 'Dein Wiederherstellungscode';

  @override
  String get recoveryBody =>
      'Schreib ihn auf oder leg ihn in deinem Passwort-Manager ab. Er wird nur jetzt angezeigt. Ohne ihn – und ohne einen Passkey, der deinen Schlüssel entsperrt – lässt sich an dich verschlüsselte Mail nicht mehr lesen.';

  @override
  String get recoveryKept => 'Ich habe den Code sicher aufbewahrt';

  @override
  String get copy => 'Kopieren';

  @override
  String get copied => 'Kopiert';

  @override
  String get done => 'Fertig';

  @override
  String get encryptedMessage => 'Verschlüsselte Nachricht';

  @override
  String get unlockToRead => 'Entsperre deinen Schlüssel, um sie zu lesen';

  @override
  String get lockedEmail =>
      'Diese Nachricht ist Ende-zu-Ende verschlüsselt. Entsperre deinen Schlüssel, um sie zu lesen.';

  @override
  String get e2eEncrypted => 'Ende-zu-Ende verschlüsselt';

  @override
  String get signatureVerified => 'Signatur geprüft';

  @override
  String get signatureUnverified => 'Signatur nicht geprüft';

  @override
  String get notSigned => 'nicht signiert';

  @override
  String get willEncrypt => 'Wird Ende-zu-Ende verschlüsselt und signiert gesendet.';

  @override
  String wontEncrypt(String reason) {
    return 'Nicht Ende-zu-Ende verschlüsselt: $reason';
  }

  @override
  String get sentEncrypted => 'Ende-zu-Ende verschlüsselt gesendet';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get calendar => 'Kalender';

  @override
  String get contacts => 'Kontakte';

  @override
  String get today => 'Heute';

  @override
  String get earlier => 'Früher';

  @override
  String get later => 'Später';

  @override
  String get allDay => 'Ganztägig';

  @override
  String get noEvents => 'Keine Termine in diesen zwei Wochen';

  @override
  String get location => 'Ort';

  @override
  String get participants => 'Teilnehmende';

  @override
  String get accept => 'Zusagen';

  @override
  String get maybe => 'Vielleicht';

  @override
  String get decline => 'Absagen';

  @override
  String get cancelled => 'Abgesagt';

  @override
  String get recurring => 'Wiederholt sich';

  @override
  String get yourAnswer => 'Deine Antwort';

  @override
  String get statusAccepted => 'zugesagt';

  @override
  String get statusTentative => 'vielleicht';

  @override
  String get statusDeclined => 'abgesagt';

  @override
  String get statusNeedsAction => 'noch keine Antwort';

  @override
  String get answerSent => 'Antwort an die Person gesendet, die eingeladen hat';

  @override
  String get searchContacts => 'Kontakte durchsuchen';

  @override
  String get noContacts => 'Keine Kontakte';

  @override
  String get emails => 'E-Mail';

  @override
  String get phones => 'Telefon';

  @override
  String get notes => 'Notizen';

  @override
  String get writeEmail => 'E-Mail schreiben';

  @override
  String get organization => 'Organisation';

  @override
  String sharedBy(String name) {
    return 'geteilt von $name';
  }

  @override
  String get newEvent => 'Neuer Termin';

  @override
  String get editEvent => 'Termin ändern';

  @override
  String get deleteEvent => 'Termin löschen';

  @override
  String get deleteEventConfirm => 'Diesen Termin löschen? Alle Eingeladenen erfahren davon.';

  @override
  String get deleteRecurringConfirm =>
      'Diesen Termin mit allen Wiederholungen löschen? Alle Eingeladenen erfahren davon.';

  @override
  String get title => 'Titel';

  @override
  String get starts => 'Beginn';

  @override
  String get ends => 'Ende';

  @override
  String get calendarField => 'Kalender';

  @override
  String get description => 'Beschreibung';

  @override
  String get invite => 'Einladen';

  @override
  String get inviteHint => 'Adressen, durch Komma getrennt – sie bekommen eine Einladung per E-Mail';

  @override
  String get repeat => 'Wiederholung';

  @override
  String get repeatNone => 'Nie';

  @override
  String get repeatDaily => 'Täglich';

  @override
  String get repeatWeekly => 'Wöchentlich';

  @override
  String get repeatMonthly => 'Monatlich';

  @override
  String get repeatYearly => 'Jährlich';

  @override
  String get saved => 'Gespeichert';

  @override
  String get deleted => 'Gelöscht';

  @override
  String get delete => 'Löschen';

  @override
  String get edit => 'Ändern';

  @override
  String get endBeforeStart => 'Das Ende liegt vor dem Beginn';

  @override
  String get recurringEditsAll => 'Änderungen gelten für alle Wiederholungen.';

  @override
  String get newContact => 'Neuer Kontakt';

  @override
  String get editContact => 'Kontakt ändern';

  @override
  String get deleteContactConfirm => 'Diesen Kontakt löschen?';

  @override
  String get name => 'Name';

  @override
  String get emailsField => 'E-Mail-Adressen';

  @override
  String get phonesField => 'Telefonnummern';

  @override
  String get onePerLine => 'Eine pro Zeile';

  @override
  String get note => 'Notiz';
}
