<!-- SPDX-License-Identifier: MIT -->
# Changelog

What changes from release to release of kernoid's apps. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org) and
go with kernoid's – the apps 0.2.0 belong to kernoid 0.2.0.

## [Unreleased]

### Added

- One event of a series is changed or deleted on its own, or the whole series – the app asks which.
- A month view of the calendar, with the chosen day's events beside the grid (below it on phones).
- Addresses and phone numbers of a contact carry their labels – work, private, and for a number mobile, fax and the
  like –, set in the form and shown on the contact.
- HTML mail is shown formatted: nothing in it runs, images from the internet load only when asked for, and a link
  shows where it goes before it opens. The plain text is a tap away.

## [0.2.0] – 2026-10-30

The first release, a preview: one Flutter app for macOS, Linux, Windows and Android (iOS builds, but installs only
signed), on kernoid's Rust SDK from crates.io (`kernoid-client`, `kernoid-e2e` 0.2.0). The builds are **not signed** –
for testing, not for data that matters; the website says how to open them.

### Added

- Signing in with kernoid's login page in the system's browser (OpenID Connect – a passkey, a password or a second
  factor, as the organisation has it) or with an app password; the login is kept in the system's key store and
  resumed at start, and signing out revokes it.
- Mail: mailboxes, messages page by page, reading as text with attachments to save; writing plain text with Cc and
  Bcc, replies, replies to all and forwards (quoted in the user's language, the thread kept) and files attached.
- End-to-end encryption without setting it up: the key made in the app with a recovery code shown once, unlocked with
  that code; encrypted mail read and its signature checked on the device; messages encrypted and signed whenever every
  recipient has a key – the compose view says so before sending.
- Calendars: two weeks as a list of days, events made, changed and deleted, invitations answered and sent.
- Contacts: search; made, changed and deleted; writing to one.
- Files: the own store, drives and what is shared, directories, saving a file.
- English and German; light and dark following the system; a layout for wide windows and one for phones.

### Known gaps

Marked `OPEN` in [docs/plan.md](docs/plan.md), among them: files in the system's file manager (the native parts),
syncing a folder, unlocking with a passkey, one instance of a recurring event on its own, a month view, HTML mail,
forwarding the attachments of an encrypted message, signed builds and the app stores.

[Unreleased]: https://github.com/kernoid/apps/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kernoid/apps/releases/tag/v0.2.0
