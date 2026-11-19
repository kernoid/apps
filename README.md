<!-- SPDX-License-Identifier: MIT -->
# kernoid apps

The **first-party apps** of [kernoid](https://kernoid.dev) – one sovereign core for mail, identity and files – licensed
under **MIT**.

> **Status: first prototype.** Signing in with kernoid's login page in the system's browser (OpenID Connect – a
> passkey, a password or a second factor; kept in the system's key store) or with an app password, mail (mailboxes, messages, reading; writing plain
> text with Cc and Bcc, replies, forwards and files attached) with end-to-end encryption (the key made here, unlocked with the recovery code; encrypted and signed whenever
> every recipient has a key), calendars (two weeks as a list of days; events made, changed, deleted and answered),
> contacts (search; made, changed, deleted; writing to one) and files (stores, directories, saving a file) on macOS,
> iOS, Linux, Android and Windows.
> Nothing to install yet. What the apps will be and how they are built is in [docs/plan.md](docs/plan.md).

## What they are

- **One Flutter app** for macOS, iOS, Linux, Android and Windows – the same functions on every one of them, with
  files in the system's file manager through a small native part per system.
- **Clients of open protocols only** – JMAP, WebDAV, CalDAV/CardDAV, OIDC – through kernoid's Rust SDK (MIT,
  `kernoid-client` and `kernoid-sync` from crates.io). They contain no code of the kernoid server, which stays
  AGPL-3.0-or-later like its terminal app.
- **End-to-end encryption without setting it up** – keys, finding and publishing them, encrypting – on
  `kernoid-e2e` (RFC 0006 of kernoid).
- **MIT**, so that they can be distributed through app stores as well – on phones and on desktops. Anyone may write
  their own apps against the same protocols.

## Build

[Flutter](https://docs.flutter.dev/get-started/install) 3.50.0 and [rustup](https://rustup.rs). The app is put together
from **kernoid's app kit** – Flutter packages in [kernoid/kernoid](https://github.com/kernoid/kernoid) (`kit/flutter/`,
RFC 0011): the frame, mail, calendars, contacts, files, the look, the strings and the Rust side (`kernoid_bridge`, on
kernoid's Rust SDK). `pubspec.yaml` takes them from the release of the same version; to build against a checkout of
kernoid/kernoid beside this one, run `scripts/kit.sh` (it writes a `pubspec_overrides.yaml`, not tracked). Then
`flutter run -d macos` (or `ios`, `linux`, `android`, `windows`); the first build compiles the Rust side, later ones
only what changed. Linux needs `libgtk-3-dev`, `libsecret-1-dev` and `libwebkit2gtk-4.1-dev`.

| Path | Content |
|---|---|
| `lib/main.dart` | which features the app has – those its server offers are shown |
| `native/apple/` | the File Provider extension of macOS and iOS (Swift) – the stores in Finder and the Files app – on the core in the kit's bridge (`rust/src/provider.rs` there); its targets are `KernoidFileProvider` in `macos/` and `ios/`, which build the bridge's crate as a static library (`build-rust.sh`) |
| `android/`, `windows/` | the DocumentsProvider and the Explorer integration around the same core |
| `integration_test/` | the app against a real kernoid, see the file's head |

Checks, as CI runs them (the kit's packages and their Rust side are checked in kernoid/kernoid):

```sh
scripts/kit.sh            # with kernoid/kernoid beside this checkout
dart format --output=none --set-exit-if-changed lib integration_test && flutter analyze lib integration_test
```

## Licence

MIT – see [LICENSE](LICENSE). Documentation prose is CC BY 4.0; the app icons are copies from [kernoid/brand](https://github.com/kernoid/brand) under CC BY-ND 4.0.
Contributions are signed off (`git commit -s`, [DCO](https://developercertificate.org/)).
