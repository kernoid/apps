// SPDX-License-Identifier: MIT
import 'package:kernoid_calendar/kernoid_calendar.dart';
import 'package:kernoid_contacts/kernoid_contacts.dart';
import 'package:kernoid_files/kernoid_files.dart';
import 'package:kernoid_mail/kernoid_mail.dart';
import 'package:kernoid_shell/kernoid_shell.dart';

/// kernoid's app: the frame of kernoid's kit with mail, calendars, contacts and files – those the server offers are
/// shown (RFC 0011). The packages are in kernoid/kernoid (`kit/flutter/`).
const features = [MailFeature(), CalendarFeature(), ContactsFeature(), FilesFeature()];

Future<void> main() => runKernoidApp(features: features);
