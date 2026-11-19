<!-- SPDX-License-Identifier: MIT -->
# CLAUDE.md – kernoid apps

Rules for working in this repository. This file is public: nothing personal goes here.

## What this is

The first-party apps of kernoid – one Flutter app for macOS, iOS, Linux, Android and Windows, with a Rust side. A
falkOSS project. Since 0.5 the app is put together from **kernoid's app kit** – Flutter packages in kernoid/kernoid
(`kit/flutter/`, RFC 0011): the frame (`kernoid_shell`), the features (`kernoid_mail`, `kernoid_calendar`,
`kernoid_contacts`, `kernoid_files`), the look (`kernoid_ui`), the strings (`kernoid_l10n`) and the Rust side
(`kernoid_bridge`). Pages, widgets, strings and the bridge are changed there, with that repository's rules; here are
`lib/main.dart` (which features), the platform folders with what belongs to this app bundle (the File Provider
extension, the DocumentsProvider, Explorer's registration, icons, entitlements), the integration test and the release. What the apps will be and in which order is in [docs/plan.md](docs/plan.md); the README has the
layout and the checks.

## Principles

- **Everything included:** one edition, every feature free; no paid tiers, licence keys or unlocks.
- **No telemetry.** Only connections that are technically needed or that users start themselves.
- **Clients of open protocols only** (JMAP, WebDAV, CalDAV/CardDAV, OIDC): no code of the kernoid server, which is
  AGPL. The protocol is the licence boundary.
- **No administration in the apps** – only the user's own account settings; nothing that acts beyond the own account.
  Administration stays in kernoid's web app and terminal app.
- **End-to-end encryption needs no setting up** in the apps (plan, section 6), on `kernoid-e2e`.
- The same functions on every platform; mobile can do what desktop can.

## Licences

- Everything here: **MIT**, an SPDX header in every own source file; REUSE checked in CI. Documentation prose in
  `docs/` is CC BY 4.0.
- The app icons (`macos/…/AppIcon.appiconset/`, `ios/…/AppIcon.appiconset/`, `android/…/mipmap-*/ic_launcher.png`,
  `windows/runner/resources/app_icon.ico`) are copies of `apps/` in [kernoid/brand](https://github.com/kernoid/brand)
  under CC BY-ND 4.0 – update them by copying, never edit them here.
- Dependencies stay permissive: the kit checks its own (`cargo deny` of the bridge in kernoid/kernoid); exceptions are
  recorded with their reason in the plan (section 7).

## Rules

- English in code, docs and commits; commits signed off (`git commit -s`).
- No personal data in tracked files (names, paths like `/Users/…`, hostnames, keys, passwords).
- Claims need a source; unverified statements are marked **OPEN**.
- Dependencies exact (`pubspec.lock` checked in) and at least 14 days old; a fix for a security advisory may be
  younger. The kit comes from kernoid/kernoid by git at the release's tag (`pubspec.yaml`, every package also in
  `dependency_overrides`, since the packages name each other by path). Never commit a `pubspec.lock` made with a
  `pubspec_overrides.yaml` (`scripts/kit.sh`): it names paths.
- **No Material, no Cupertino** (maintainer, 2026-11-13): the app is built on Flutter's `widgets` layer and the kit's
  `kernoid_ui` alone – pages import `package:kernoid_ui/ui.dart`, never `material_ui`, `cupertino_ui` or `package:flutter/material.dart` and
  `cupertino.dart`. `kernoid_ui` holds the frame (`KApp` on `WidgetsApp`, `KPageRoute`, `KScaffold`, `KToast`), the look
  (`KTokens` through `KTheme`, `context.k`: the web app's values, light and dark), text input on `EditableText`
  (`KTextField`, `KTextFormField`, `KSelectable` – the platform's gestures, kernoid's handles and menu), dialogs,
  menus and choices (`showKDialog`, `KDialog`, `showKMenu`, `KMenuButton`, `KSelect`), date and time
  (`showKDatePicker`, `showKTimePicker`, `KTime`) and the controls (`KButton`, `KIconButton`, `KSwitch`, `KCheckbox`,
  `KRadioRow`, `KToggleRow`, `KChip`, `KSpinner`, `KProgressBar`, `KTooltip`, `KRefresh`, `KTappable`, …). Icons are
  Lucide (`lucide_icons_flutter`), text IBM Plex. Something new that is seen goes into `kernoid_ui`. A dependency that
  brings Material is replaced where it can be (PDFs: `pdfrx_engine` instead of `pdfrx`); what is left –
  `window_manager` and `flutter_widget_from_html_core` import Flutter's own `material.dart` – is used without its
  Material widgets (the HTML view's tooltip and loading come from `kernoid_ui`).
- Dart lines up to 120 characters (`analysis_options.yaml`), as in the kit.

## Building – what is not obvious

- **Against the kit of a checkout:** `scripts/kit.sh` (kernoid/kernoid beside this checkout, or `KERNOID_DIR`) writes a
  `pubspec_overrides.yaml` naming every package by path; CI does it with the checkout of `KERNOID_REF`. A change of the
  kit and of the app go together without a release in between.
- Rust is pinned in the bridge's `rust/rust-toolchain.toml`; cargokit is told the same version in `rust/cargokit.yaml`, else it
  builds with whatever toolchain it finds. It runs `rustup run <version> cargo`, and cargo finds `rustc` on `PATH`: a
  Rust of Homebrew before `~/.cargo/bin` has no targets for iOS or Android, and the build fails with "can't find crate
  for `core`". Put `~/.cargo/bin` first.
- The protocols are kernoid's Rust SDK (`kernoid-client`, with `kernoid-e2e`), which the kit's bridge takes by path in
  kernoid/kernoid; `rust/src/api/` there only translates them for Dart.
- Signing in with OpenID Connect goes through flutter_web_auth_2: `dev.kernoid.kernoid:/oauth` on Apple's systems and
  Android (the `CallbackActivity` in `AndroidManifest.xml`), `http://127.0.0.1:<port>/oauth` on desktops. The system's
  browser is out of the integration test's reach; the protocol is tested in kernoid's SDK against a real kernoid.
- The login is kept with flutter_secure_storage (`app/kept_login.dart`): Keychain on Apple's systems – on macOS the
  login keychain, as the data protection keychain needs a signing team's entitlement –, Android Keystore, Windows
  Credential Manager, Secret Service on Linux (`libsecret-1-dev` to build; flutter_web_auth_2 needs `libwebkit2gtk-4.1-dev`). Every renewal rotates the refresh token
  and is kept again; one used before ends the login at the server.
- Files are attached through file_selector: the macOS sandbox lets the app read and write what the user picked
  (`com.apple.security.files.user-selected.read-write`) – a folder kept in step is reached again after a restart
  through a security-scoped bookmark (`files.bookmarks.app-scope`, the channel `dev.kernoid.kernoid/bookmarks` in
  `macos/Runner/MainFlutterWindow.swift`). A widget test cannot drive the system's dialog, so the tests give paths to
  the bridge and to `SyncFolders` instead.
- The File Provider extension (`native/apple/`, target `KernoidFileProvider` in `macos/` and `ios/`) links the bridge's
  crate as a static library of its own: a build phase runs `native/apple/build-rust.sh` (it finds the package
  `kernoid_bridge` through `.dart_tool/package_config.json`; `cargo rustc --release --crate-type staticlib` for
  `KERNOID_RUST_TARGET` of `FileProvider/FileProvider.xcconfig`, into the project's temporary folder),
  and the xcconfig links it – without `$(inherited)`, whose pods' `-framework kernoid_bridge` would bind it to
  cargokit's build for the app. The app and the extension share an app group and a keychain group, which Xcode
  accepts only with a signing team: builds are unsigned (`KERNOID_SIGNED = NO` in `Signing.xcconfig`) and take the
  entitlements without the groups; with a team set `KERNOID_SIGNED = YES` and `DEVELOPMENT_TEAM`, and the
  `*-Signed.entitlements` are taken. The extension cannot run unsigned.
- An iOS build needs a `libc` new enough for `backtrace` on iOS – do not set it back below the version in the bridge's
  `rust/Cargo.lock`.
- Android in CI builds for arm64 only and without debug info; the runner needs disk space freed first.
- `integration_test/app_test.dart` runs the app against a real kernoid – how is in its head. Too many failed logins
  lock an address for some minutes (HTTP 429). On macOS the app's sandbox puts screenshots below
  `~/Library/Containers/dev.kernoid.kernoid/Data/tmp/`.

## Checks

```sh
scripts/kit.sh   # kernoid/kernoid beside this checkout
dart format --output=none --set-exit-if-changed lib integration_test && flutter analyze lib integration_test
```

The kit's packages and the bridge's Rust side are checked in kernoid/kernoid (CI's job `flutter`).
