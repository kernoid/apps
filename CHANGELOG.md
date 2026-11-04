<!-- SPDX-License-Identifier: MIT -->
# Changelog

What changes from release to release of kernoid's apps. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org) and
go with kernoid's – the apps 0.2.0 belong to kernoid 0.2.0.

## [Unreleased]

### Added

- Folders of this computer kept in step with the stores (desktops): chosen in the account, one per store, synced by
  kernoid's `kernoid-sync` every few minutes while the app is open and on demand – moves stay moves, transfers that
  broke off go on, both versions are kept when a file changed on both sides, vaults are synced while the key is
  unlocked. On macOS the app may now write to folders the user chose and keeps a bookmark to reach them again. Needs
  kernoid's Rust SDK 0.2.4.
- The stores in Finder and the Files app (macOS, iOS): a File Provider extension, one place per store, files shown
  before they are downloaded and fetched when opened, made, changed, moved and deleted there – deleted into kernoid's
  Trash, from there for good. Turned on in the account ("Files in Finder"), it signs in once more in the browser, as
  the extension keeps a login of its own. Vaults are shown locked. The builds are unsigned and the extension needs a
  signing team to run, so it is **not usable yet**.

## [0.2.3] – 2026-11-04

With kernoid 0.2.3 and its Rust SDK (`kernoid-client`, `kernoid-e2e` 0.2.3 from crates.io): files as far as the web app
has them – a viewer, dragging and dropping, whole folders, vaults. The builds are still **not signed** – for testing,
not for data that matters.

### Added

- A viewer for files: text (the first megabyte), pictures to zoom and PDFs (pdfrx) open in the app; audio, video and
  everything else go to another app of the system – the one for its type on desktops, the share sheet on phones.
- Files dropped onto the list are uploaded where it is (desktop_drop); on desktops a file or folder is moved by
  dragging it onto a folder or onto a step of the path above the list.
- Vaults (RFC 0006, 6): folders only their members read, made in the app with the account's key – names and contents
  encrypted and decrypted on the device, a vault's key given to the people it is shared with, the key unlocked from
  the list when it is needed. In a vault there are no links, versions or copies, and nothing moves out of it but into
  the trash, as in the web app. Needs kernoid's Rust SDK 0.2.3.
- Whole folders are uploaded – dropped onto the list or, on desktops, chosen with a button –: a folder of the same
  name there is filled, not made twice, and the systems' own files (`.DS_Store`, `Thumbs.db`, `desktop.ini`) are left
  out.

### Changed

- In a vault the list shows no size: the server knows only that of the encrypted content.
- The integration test waits for what it taps and checks what it types – it failed now and then at the first login.

## [0.2.2] – 2026-10-31

With kernoid 0.2.2 and its Rust SDK (`kernoid-client`, `kernoid-e2e` 0.2.2 from crates.io): kernoid's own look, and
mail, files and the account as far as the web app has them. The builds are still **not signed** – for testing, not for
data that matters.

### Changed

- On kernoid's Rust SDK 0.2.2 (`kernoid-client`, `kernoid-e2e` from crates.io), released with kernoid 0.2.2.
- kernoid's own look instead of Material's: the web app's colours (dark, and light when the system is), IBM Plex,
  Lucide icons, a side bar with the word mark on wide screens and a bar of the sections on narrow ones, and widgets of
  its own (`lib/ui`). Mail shows its folders as a tree, its messages with avatars and an unread mark.

### Added

- Shared mailboxes: each one the user may read appears under its name with its folders; its messages are read,
  answered and forwarded from the user's own account (a forward fetches their attachments from the shared mailbox).
- Searching mail, over the whole mailbox.
- Several messages at once – Ctrl or ⌘ and Shift on desktops, a long press on phones –: marked read or unread,
  flagged, moved to a folder, deleted (into the Trash; out of the Trash or Junk for good, once confirmed).
- Mail folders are made, renamed, moved and deleted (with their messages, once confirmed), and the Trash and Junk
  emptied – from a folder's menu (right click, or a long press on phones; a page of its own on phones), in the own
  mailbox and in shared ones the user may change.
- A refused login says that the address or the app password is wrong, in the user's language.
- Files as the web app has them: the own store, the tenant's drives and what others share, side by side on wide
  screens and in a menu on phones; new folders, uploads with their progress, searching names and contents; for each
  file or folder, as far as the user's rights go: sharing with people and groups, links for people without an account
  (with an expiry and a password), versions (saved, or made current again), moving – and copying to another store –,
  renaming, deleting into the Trash and out of it for good. OPEN: vaults, a viewer, dropping files onto the window.
- The account page in kernoid's look: light, dark or as the system (kept on the device), the vacation response with
  its dates, subject and text, the end-to-end key; with a login of OpenID Connect also the name, the picture, the
  language of kernoid's emails and the mail settings (the address mail comes from, undo sending, how long the Trash
  keeps mail) – with an app password, given to other programs, those stay in the web app. Password, second factors,
  passkeys, app passwords and sessions are the web app's, a click away. OPEN: cutting a picture to a square.

- The platforms of falkOSS's starter pack: macOS 27 and later on Apple silicon only (no Intel build – half the build
  and the app's size), iOS 27 and later, Android 13 (API 33) and later on 64-bit ARM only, Windows 11 and later on
  x64, Linux on x64 and arm64.

## [0.2.1] – 2026-10-31

With kernoid 0.2.1 and its Rust SDK (`kernoid-client`, `kernoid-e2e` 0.2.1 from crates.io). The builds are still
**not signed** – for testing, not for data that matters.

### Added

- One event of a series is changed or deleted on its own, or the whole series – the app asks which.
- A month view of the calendar, with the chosen day's events beside the grid (below it on phones).
- Addresses and phone numbers of a contact carry their labels – work, private, and for a number mobile, fax and the
  like –, set in the form and shown on the contact.
- A forward of an end-to-end encrypted message carries its attachments – decrypted in memory, inside the encrypted
  forward, never on disk.
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

[Unreleased]: https://github.com/kernoid/apps/compare/v0.2.3...HEAD
[0.2.3]: https://github.com/kernoid/apps/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/kernoid/apps/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/kernoid/apps/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/kernoid/apps/releases/tag/v0.2.0
