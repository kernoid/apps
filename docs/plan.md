<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# kernoid apps – plan

What the first-party apps of kernoid are, how they are built and in which order. The design of kernoid itself is in
the RFCs of [kernoid/kernoid](https://github.com/kernoid/kernoid/tree/main/rfcs); the files and their sync protocol
in [RFC 0005](https://github.com/kernoid/kernoid/blob/main/rfcs/0005-files.md). Statements marked **OPEN** are not
decided or not verified.

## 1. Place in kernoid

kernoid is split along one line – **open protocols** – with one shared client library on the permissive side:

| Part | Repository | Licence | Content |
|---|---|---|---|
| Server | `kernoid/kernoid` | AGPL-3.0-or-later (parts taken over from Stalwart AGPL-3.0-only) | identity, mail, calendars, contacts, files; the web app |
| Terminal app | `kernoid/kernoid` | AGPL-3.0-or-later | `kernoid-tui`, on the Rust SDK |
| Rust SDK | `kernoid/kernoid`, Cargo workspaces of their own | **MIT** | `kernoid-client` (the protocols), `kernoid-sync` (files kept in step), `kernoid-e2e` (end-to-end encryption, RFC 0006; today `apps/e2e`); on crates.io |
| TypeScript SDK | `kernoid/kernoid` (`web/sdk`) | MIT | for other login pages and web clients |
| **Apps** | `kernoid/apps` (this one) | **MIT** | one Flutter app for macOS, iOS, Linux, Android and Windows |

- The apps speak JMAP (mail, calendars, contacts, files with `FileNode`), WebDAV, CalDAV/CardDAV and OIDC – through
  the Rust SDK, which is written from the specifications and kernoid's RFCs (their text is CC BY 4.0).
- The SDK lives beside the server so that a protocol change lands in one commit with its server side and is tested
  against the real server in CI. It is a workspace of its own with its own lock file and a `deny.toml` that admits
  permissive licences only, and CI checks that it reaches no server crate. It moves to a repository of its own only if
  kernoid's extensions become a specification of their own.
- The apps contain **no server code** and depend on the SDK by version from crates.io, not on the server's
  repository.
- Being MIT, the apps can be distributed through **app stores** – on phones and on desktops – which the AGPL is widely
  held not to allow (**OPEN**: review by someone who knows licence law, as for spezado). The terminal app stays
  AGPL; it does not go into stores.
- Their dependencies are **permissive** as well: `cargo deny` for Rust, a licence check of `pubspec.lock` for Dart
  (**OPEN**: tool). Exceptions are recorded with their reason (section 7: dbus on Linux, MPL-2.0).

## 2. Platforms and order

The versions and architectures built for are falkOSS's (starter pack, `docs/practices.md`, Platforms): macOS 27 and
later on Apple silicon (no Intel build), iOS and iPadOS 27 and later, Android 13 (API 33) and later on `arm64-v8a`,
Windows 11 and later on x64, Linux on x64 and arm64; x64 for Android and Arm64 for Windows once the community asks.
The Rust toolchain lists only these targets.

All five platforms are built **from the start and at the same time** – one code base, one CI matrix. Where work has to
be ordered (native parts, polish, store release), the priority is:

1. **macOS**
2. **iOS**
3. **Linux**
4. **Android**
5. **Windows**

**Feature parity:** the mobile apps can do everything the desktop apps can – mail, calendars, contacts, files with
sharing, links and versions, and the user's own account settings. The layout adapts to the screen; the functions do
not differ.

**No administration:** managing tenants, instances, domains, accounts of others, modules or policies stays in the
web app and the terminal app. The apps carry the user's own account settings only – profile, sign-in methods, app
passwords, devices, language, vacation response – and nothing with an effect beyond that account.

## 3. When

The app is built now and released **with the first stable version** (maintainer, 2026-10-30). 1.0 comes once falkOSS
is incorporated and holds the app stores' developer accounts – publishing in the stores needs that legal entity.
Until then, in this order:

1. **The Rust SDK** in `kernoid/kernoid`: the protocol layer of the terminal app became `kernoid-client`
   (`apps/client`), async; the terminal app uses it and is AGPL like the rest of the repository (done 2026-10-30).
2. **`kernoid-sync`** (`apps/sync`): local state, changes, conflicts – tested against a real kernoid in CI (first
   version 2026-10-30; moves as moves, resumed transfers, vaults and the file systems' name rules 2026-11-04, for
   kernoid's next SDK release – OPEN: content hashes, file ids on Windows, vault contents in pieces).
3. **This repository:** the Flutter app with mail, calendars and contacts, files inside the app – with end-to-end
   encryption (section 6) from its first version, not added later.
4. **System integration** of files (section 5), in the order of section 2.

## 4. Layout

```
apps/
├── lib/                 the Flutter app: UI, state, i18n (en, de) – one code base for all five platforms
├── rust/                one crate, `kernoid_bridge` (MIT), its own lock file
│   ├── src/api/           the API Dart sees, generated with flutter_rust_bridge, on kernoid-client and kernoid-sync
│   ├── src/provider.rs    the core of the file shells: JSON messages through a C boundary (section 5)
│   └── src/provider/      its JNI functions for Android (`jni.rs`) and the Cloud Files shell for Windows
├── native/apple/        the File Provider extension (Swift), shared by macOS and iOS
├── macos/, ios/         Flutter runners; the `KernoidFileProvider` extension target
├── android/             Flutter runner; the DocumentsProvider in Kotlin
├── windows/, linux/     Flutter runners
├── test/, integration_test/
└── docs/                this plan, later the user documentation
```

`unsafe_code` only where foreign functions are called: the C boundary, JNI and the calls to Windows.

**The first prototype (2026-10-30)** has a simpler shape: `rust/` is one crate, `kernoid_bridge` – the API Dart sees
(`src/api/`), on `kernoid-client` – by commit at first, from crates.io since 0.2.0 – (its own JMAP client
before, which became the SDK's); `rust_builder/` is flutter_rust_bridge's plugin with cargokit, which builds `rust/` for each
platform (changed to build with the exact Rust of `rust/rust-toolchain.toml`). It signs in with an app password
and does mail (mailboxes, messages, reading, sending plain text) and files (stores, directories, saving).
End-to-end encrypted mail came the same day, on `kernoid-e2e` (from crates.io
since 0.2.0): the key made in the app with a recovery code shown once (and the tenant's copy when its policy asks),
unlocked with that code and kept in memory only, encrypted mail shown as locked until then, read and its signature
checked on the device, and sent encrypted and signed whenever every recipient has a key – the compose view says so
beforehand. Unlocking with a passkey (PRF) and a copy in the system's key store, vaults, encrypted calendars and the native
shells follow. Signing in with OpenID Connect came the same day: kernoid's login page in the system's browser
(flutter_web_auth_2 – ASWebAuthenticationSession, Custom Tabs, a loopback listener on desktops), kernoid's built-in
client of the apps and the scope `urn:kernoid:data`; the access token is renewed while the app runs, and the login is
kept in the system's key store (the refresh token, rotated and kept again with each renewal) and resumed at start;
signing out revokes it. Calendars and contacts came on the SDK (2026-10-30): the
calendars as two weeks of days with recurring events as their instances and all-day events as dates, invitations
answered from the event, events made, changed and deleted (inviting people by address); contacts with search,
made, changed and deleted, an email started from an address. On 2026-10-31 followed one instance of a recurring event
changed or deleted on its own, a month view (the chosen day's events beside or below the grid) and the labels of
addresses and numbers in the contact form. Writing mail grew the same day: replies, replies to all
(without the user's own addresses) and forwards – quoted in the user's language, the thread kept, a forward carrying
its attachments – on the SDK's `reply` (shared with the terminal app), Cc and Bcc, and files of the device attached
through file_selector – inside the encrypted message when it goes end-to-end encrypted, uploaded otherwise. HTML mail is
shown since 2026-10-31 (flutter_widget_from_html_core: drawn as widgets, nothing run; images from the internet only
when the user asks, none from the device; a link shows its address before it opens). A forward of an encrypted message carries
its attachments too: decrypted in memory and put inside the encrypted forward (the SDK's `send_with`, kernoid 0.2.1),
never written to disk decrypted. OPEN: writing HTML.

## 5. Files in the operating system

What makes a sync client more than a folder is the **integration into the operating system**: files appear before they
are downloaded, open on demand and can be freed again. Every system offers this differently, and on Apple's systems
outside the app's own process – where no Flutter engine runs. These parts are therefore native, but thin: everything
that decides – what changed, what to download, what conflicts – is in `kernoid-sync`.

| Priority | System | Interface | Runs in | Shell |
|---|---|---|---|---|
| 1 | macOS 11+ | File Provider, `NSFileProviderReplicatedExtension` | an app extension, started by the system | Swift (`native/apple/`) |
| 2 | iOS/iPadOS 16+ | File Provider, the same API | an app extension with a tight memory limit | Swift (`native/apple/`) |
| 3 | Linux | no common interface | a folder kept in step in the background; placeholders through FUSE (**OPEN**, and whether Flatpak allows it) | Rust |
| 4 | Android | `DocumentsProvider` (Storage Access Framework) | the app's process, started by the system without the UI | Kotlin |
| 5 | Windows 10 1709+ | Cloud Files API (`cfapi`): sync root, placeholders, hydration callbacks | a small provider started at login | Rust |

```
                 Flutter UI (Dart)                        the system's file manager
                        │                                           │
               flutter_rust_bridge           File Provider (Swift) · DocumentsProvider (Kotlin) · cfapi · Linux
                        │                                           │
                        └──────────────── rust/ ────────────────────┘
                                           │
                          kernoid-sync · kernoid-e2e · kernoid-client   (crates.io, MIT)
                                           │
                                     JMAP over HTTPS ── kernoid
```

`kernoid-sync` builds on what kernoid offers (RFC 0005):

- **Changes:** `FileNode/changes` from a state; when the state is too old (`cannotCalculateChanges`), a full
  `FileNode/query` and comparison. Push (EventSource or WebSocket) only says *that* something changed.
- **Transfers:** uploads and downloads in pieces (`Blob/upload` and ranges, RFC 9404), resumed after an interruption.
- **Conflicts:** a local change based on an older state than the server's is kept as a copy beside the server's
  version – never merged, never lost. The versions on the server help to recover.
- **Stores:** own files, drives and files shared with the user are roots of their own; rights (`mayRead`,
  `mayWrite`, …) decide what the shell offers.
- **Local state:** SQLite with the server's id, `blobId` and state per node and the journal state per store.

What blocked the shells (2026-11-04), and where they stand:

- **Swift/Kotlin ↔ Rust:** UniFFI is MPL-2.0 (section 7); a C boundary by hand was chosen instead (2026-11-04). The core
  of the shells is `rust/src/provider.rs`: JSON messages through two C functions (`kernoid_provider_call`,
  `kernoid_provider_free`) for Swift, JNI for Kotlin, a plain call for Rust – stores, items, changes since an anchor,
  content into a file, items made, changed, moved and deleted.
- **Apple:** a File Provider extension runs only in an app signed by a development team, with an app group and a
  keychain group the app and the extension share. The builds are unsigned; falkOSS's team comes with its founding.
  **Built (2026-11-04), not yet run:** `native/apple/` – an `NSFileProviderReplicatedExtension` (`FileProvider/`), the
  same Swift for macOS and iOS, as the target `KernoidFileProvider` in both runners, linking `rust/` as a static
  library (`build-rust.sh`, a build phase). One domain per store (its identifier the store's id); the top of a store
  is the root container, its Trash the trash container. The working set is the whole store: changes come from
  `FileNode/changes` with kernoid's state as the anchor (too old: the system enumerates again). Deleting outside the
  Trash moves into kernoid's Trash, as `kernoid-sync` does; deleting in the Trash destroys. The app turns it on in the
  account ("Files in Finder", `lib/app/file_provider.dart`, the channel `dev.kernoid.kernoid/fileprovider`): it signs
  in once more in the browser and hands that login to the extension through the shared keychain – never its own,
  since kernoid rotates refresh tokens. The system may run the extension of each domain in a process of its own, so
  the extension's calls hold a lock in the app group's container, the core renews nothing in the background
  (`renew: false`), and a process opens again with the newest kept login when it changed or the access token expired.
  The groups need a team: `Signing.xcconfig` (`KERNOID_SIGNED`) picks the entitlements with or without them, and
  unsigned builds – CI's – take those without.
  **OPEN**: running and testing it with a team (a maintainer's personal one until falkOSS's); vaults (shown locked –
  their key from a `device:` copy in the keychain group, section 6); the calls one after another under the lock, so a
  long download holds up the other domains; changes from the server reach the system only when it asks or the app
  signals (after its own file list loads) – push to the extension; progress and cancelling of transfers; the
  extension's memory limit on iOS; a domain per store of one account only (several accounts); the name of the
  trash container (English only); whether the system really runs the domains in processes of their own.
- **Besides the shells:** a folder kept in step by the app itself, on every desktop (Linux's row above) – `kernoid-sync`
  in the app's process through the bridge, a round every few minutes and on demand, a folder chosen per store in the
  account (`lib/app/sync_folders.dart`, begun 2026-11-04). On macOS the sandbox gives `files.user-selected.read-write`
  and a security-scoped bookmark keeps the folder across starts; **OPEN**: whether a bookmark of an ad-hoc signed build
  survives an update. Rounds follow kernoid's pushes and changes in the folder; a tray icon and start at login keep it
  going without the window (built 2026-11-04).

**Android, built (2026-11-04):** the DocumentsProvider needs neither a signing team nor UniFFI – it runs in the app's
own process and reaches the core (`rust/src/provider.rs`) through two JNI functions written with the jni crate
(`rust/src/provider/jni.rs`, MIT OR Apache-2.0, already a dependency of reqwest on Android). `KernoidDocumentsProvider`
(Kotlin) shows one root per store, lists, opens (content fetched into the cache; written content uploaded when the
file is closed), creates, renames, moves within a store and deletes into the store's Trash; vault items are listed as
locked. It has a login of its own: the account page signs in once more with OpenID Connect and hands that login over
(`lib/app/documents_provider.dart`); the provider keeps it encrypted with a key of the Android Keystore and keeps every
renewal the core reports. The same JNI boundary hands the JVM to rustls-platform-verifier, which reqwest checks
certificates with on Android – needed by the app itself too; its Kotlin part comes from the rustls project's Maven
repository on GitHub. **Run 2026-11-13** in an emulator (Android Automotive 15, the only complete image at hand – no
Files app there, so through the system's document picker): the app logs in (app password and OpenID Connect, kept
across a restart), verifies certificates, and the provider lists, opens, writes, renames, moves and deletes into the
Trash; files lacked rights until the core gave them their directory's. **OPEN**: a phone image or device and the real
Files app; the system's browser in the OpenID Connect login; changes made elsewhere reach the Files app only
when it asks again (no `changes` rounds or push yet); a file whose upload fails on close is dropped, not kept for
another try; moving between stores; search (`FLAG_SUPPORTS_SEARCH`), recent files, thumbnails; a renewal in flight
while the idle session closes (after a minute) is lost with it and ends the login.

**Windows (built 2026-11-04, not yet run on Windows):** the Cloud Files shell is Rust in the app's crate
(`rust/src/provider/cloud_files.rs`, the calls to Windows in `cloud_files/system.rs` with the `windows` crate) and a
client of the shells' core (`rust/src/provider.rs`) like the others. In the account, “Files in Explorer” makes a login
of its own with kernoid's login page – never the app's, as two holders would end it at the next renewal – which the
shell keeps in the app's support directory, protected with DPAPI, together with each store's anchor and tree.

- **Sync roots:** one per store below `%USERPROFILE%\kernoid` (`CfRegisterSyncRoot`, full hydration, the whole
  namespace placed by the shell – no FETCH_PLACEHOLDERS), connected while the app is open (`CfConnectSyncRoot`).
- **Placeholders:** a round every minute asks for `changes` since the anchor (all of a store when it is new or the
  anchor too old) and makes, renames, moves, updates or removes placeholders (`CfCreatePlaceholders`,
  `CfUpdatePlaceholder` with dehydration when the content changed at kernoid and not here). Vault items, the Trash
  and names Windows refuses are not shown.
- **Content:** FETCH_DATA fetches the item through the core into a temporary file and hands it over in pieces of 4 MiB
  (`CfExecute`, TRANSFER_DATA), with progress.
- **Changes in Explorer:** NOTIFY_DELETE puts the item into the store's Trash; NOTIFY_RENAME renames or moves it at
  kernoid (out of the stores, the Recycle Bin included: into the Trash; into another store: refused). New files and
  folders are found by a scan after each round, uploaded and turned into placeholders; changed files are uploaded
  again.

**OPEN**: run and test it on Windows at all (only type-checked so far, and only with the core stubbed: the C parts of
the crate do not build for `x86_64-pc-windows-msvc` on macOS); the registration with `StorageProviderSyncRootManager`
for Explorer's navigation pane and status icons; which access a handle needs for `CfConvertToPlaceholder` and
`CfUpdatePlaceholder`; whether the platform sends the provider's own renames and deletions back to it (guarded either
way); whether a placeholder moved out of a root is always hydrated first; conflicts kept as copies (today the newer
upload wins and the server keeps the older as a version); deletions while the shell does not run; stores no longer
reached; several accounts on one Windows user; moving between stores; vaults (section 6); push instead of a timer; a
provider started at login, without the app; the platform's own pin and free-up commands.

## 6. End-to-end encryption

End-to-end encryption is **a focus of the apps**. kernoid's server side is in
[RFC 0006](https://github.com/kernoid/kernoid/blob/main/rfcs/0006-end-to-end-encryption.md): OpenPGP (RFC 9580) with
post-quantum keys (RFC 9980), keys made only by clients, protected copies of the secret key on the server, WKD and
Autocrypt, encryption of mail on arrival, vaults for files, encrypted calendars and address books. What a user of
Thunderbird or another client has to set up by hand – make a key, publish it, find the keys of others, carry the key
to the next device, remember to encrypt – the apps do **by themselves**, because they speak kernoid's own extension
(`https://kernoid.dev/jmap/openpgp`). In the apps end-to-end encryption has no switch: they understand it. The
settings of RFC 0006 exist for other software.

**One implementation:** `kernoid-e2e` (MIT, rpgp), the same library the web app uses as WebAssembly and the terminal
app as a library – here through `rust/bridge` for Dart and the C boundary of `rust/src/provider.rs` for the native shells. Secret keys stay in Rust
memory; Dart sees fingerprints, never key material.

| What | In the apps |
|---|---|
| **Key** | made at the first login when the account has none, kind `pqc` by default (RFC 0006, 4.1); the recovery code shown once and asked back |
| **Unlocking** | with the passkey the user logs in with (PRF extension, RFC 0006, 4.2) – nothing to type; a `device:` copy whose passphrase lives in the platform's key store – Keychain on macOS and iOS, Android Keystore, Windows (**OPEN**: DPAPI or TPM), Secret Service on Linux. This answers RFC 0006's **OPEN** “the platform's key store” for the native apps |
| **Next device** | logs in with a passkey and unlocks the stored copy; without one, the recovery code |
| **Mail, sending** | encrypted and signed automatically when every recipient has a key (`OpenPgpKey/lookup`, WKD for others); drafts and Sent encrypted to the sender; the compose view shows before sending whether a message goes end-to-end encrypted |
| **Mail, reading** | lists from `kernoid:encryptedSummary`, messages decrypted on the device with header protection (RFC 9788); signatures shown as verified or not |
| **Search** | over what the device has decrypted, in a local index that is itself encrypted at rest (**OPEN**: how – RFC 0006, 5.4) |
| **Vaults** | the File Provider extensions, the DocumentsProvider and the Windows and Linux providers decrypt names and content themselves, so vault files open in any program on the device; they reach the key through the platform's key store (on Apple a keychain group shared by app and extensions). Sharing a vault encrypts its key to the new member's key – the apps do it when they see a waiting grant |
| **Encrypted calendars and address books** | decrypted on the device; free/busy and queries by time computed there; invitations to people outside sent by the app (RFC 0006, 7) |
| **Links** to files in vaults | the file's session key in the URL fragment (RFC 0006, 6) |
| **Tenant recovery** | when the tenant's policy requires it, the apps store the `tenant` copy (RFC 0006, 8.2). Making the tenant's recovery key and restoring an account's key are administration – the terminal app and the web app, not these apps |

**Trust:** the apps are the answer to RFC 0006, 9 – their code does not come from the server they protect against.
Builds are made in CI from tagged source; **OPEN**: reproducible builds and published hashes, so that what a store
delivers can be checked against the source.

**OPEN**: passkeys with PRF from Flutter – no package known to support it, so likely a native part per platform
(Apple's AuthenticationServices, Android's Credential Manager; Windows and Linux: which authenticators offer PRF);
the order in which the vault and calendar parts follow mail.

## 7. Building blocks

| Block | Choice | Licence | Note |
|---|---|---|---|
| UI | Flutter 3.50, Dart 3.14, its `widgets` layer only – no Material, no Cupertino (decided 2026-11-13); kernoid's own widgets in `lib/ui/` | BSD-3-Clause | one code base for five platforms, accessibility on all of them; the look is the web app's on every platform |
| Dart ↔ Rust | flutter_rust_bridge 2.13 | MIT | async and streams in both directions |
| Swift/Kotlin ↔ Rust | a C boundary by hand: JSON through two C functions (`rust/src/provider.rs`), JNI for Kotlin | MIT | chosen 2026-11-04 instead of UniFFI 0.32 (MPL-2.0, file-level copyleft) |
| Kotlin ↔ Rust (built) | JSON messages over JNI, jni 0.22.4 | MIT OR Apache-2.0 | the core of the shells (`rust/src/provider.rs`); jni came already with reqwest on Android |
| Certificates on Android | rustls-platform-verifier 0.7.1 and its Kotlin part 0.2.0 (the rustls project's Maven repository on GitHub) | MIT OR Apache-2.0 | reqwest's verifier; the JVM is handed to it at start, the Kotlin part's version checked against `rust/Cargo.lock` |
| Async runtime, HTTP | tokio, reqwest 0.13 with rustls (AWS-LC, post-quantum key exchange preferred) – through kernoid's SDK | MIT/Apache-2.0, ISC | async – the engine waits on many transfers and push at once |
| Local state | SQLite | public domain | one file on every system |
| Sign-in | OIDC with PKCE as a public client; tokens in the system's keychain | – | as RFC 0001 describes for apps |
| Viewing files | pdfrx_engine 0.7 with pdfium_flutter 0.4 (PDFium, prebuilt and fetched at build time with its hash), the pages drawn by the app itself – pdfrx's viewer brings Material; text and pictures by Flutter | MIT; PDFium BSD-3-Clause/Apache-2.0 | audio and video go to another app of the system (decided 2026-11-04): no player on all five systems without LGPL libraries; share_plus 13.3 (BSD-3-Clause) for the share sheet on phones |
| Dropping files | desktop_drop 0.8.4 – 0.9 needs a cross_file that file_selector does not take yet | Apache-2.0; on Linux dbus (MPL-2.0, file-level copyleft, Dart source unchanged) | moving inside the app with Flutter's own drag and drop |
| Windows' Cloud Files, DPAPI | `windows` 0.62 (Microsoft), only built for Windows | MIT OR Apache-2.0 | the Explorer shell of section 5 |
| Tray, start at login | tray_manager 0.5.3 and window_manager 0.5.2 – 0.6 and later build a native library (nativeapi) on every platform; start at login without a package (SMAppService, the registry, XDG Autostart) | MIT; on Linux the system's libayatana-appindicator (LGPL, linked as WebKitGTK is) | decided 2026-11-04 |

All versions are exact and at least two weeks old when taken, as in kernoid.

## 8. Distribution

- **Releases** as tags `vX.Y.Z` with `CHANGELOG.md`; archives and installers on GitHub from the start.
- **Stores:** App Store for iOS **and macOS**; Google Play and F-Droid; Flathub; Microsoft Store (**OPEN**: Cloud Files
  from a packaged app). Outside the stores, macOS builds are signed and notarised with falkOSS's Developer ID and
  Windows builds signed – once falkOSS is founded.
- **Name and icon** from `kernoid/brand` as copies under CC BY-ND 4.0, as in the other repositories.

## 9. Principles

- Everything the apps can do, kernoid offers to every client – no private API for first-party apps.
- No telemetry, no third-party services. Push (RFC 0007, decided 2026-10-30): UnifiedPush and Web Push need no
  setting; APNs and FCM only where the operator set their own keys or a relay – nothing by default, and falkOSS runs
  no relay for now.
- English source strings, translations beside them (en, de).
