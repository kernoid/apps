<!-- SPDX-License-Identifier: MIT -->
# CLAUDE.md – kernoid apps

Rules for working in this repository. This file is public: nothing personal goes here.

## What this is

The first-party apps of kernoid – one Flutter app for macOS, iOS, Linux, Android and Windows, with a Rust side. A
falkOSS project. What the apps will be and in which order is in [docs/plan.md](docs/plan.md); the README has the
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
  `docs/` is CC BY 4.0; `rust_builder/cargokit/` is MIT OR Apache-2.0 (Matej Knopp), changed for an exact Rust version.
- The app icons (`macos/…/AppIcon.appiconset/`, `ios/…/AppIcon.appiconset/`, `android/…/mipmap-*/ic_launcher.png`,
  `windows/runner/resources/app_icon.ico`) are copies of `apps/` in [kernoid/brand](https://github.com/kernoid/brand)
  under CC BY-ND 4.0 – update them by copying, never edit them here.
- Dependencies stay permissive: `cargo deny` for Rust (`rust/deny.toml`); exceptions are recorded with their reason
  in the plan (section 7).

## Rules

- English in code, docs and commits; commits signed off (`git commit -s`).
- No personal data in tracked files (names, paths like `/Users/…`, hostnames, keys, passwords).
- Claims need a source; unverified statements are marked **OPEN**.
- Dependencies exact (`=x.y.z` in `rust/Cargo.toml`, `pubspec.lock` checked in) and at least 14 days old –
  `scripts/check-age.py` after changing `rust/Cargo.lock`; a fix for a security advisory may be younger.
- `lib/src/rust/` and `rust/src/frb_generated.rs` are generated (`flutter_rust_bridge_codegen generate`, see
  `flutter_rust_bridge.yaml`) – change `rust/src/api/` and generate again, never edit them.
- Strings in `lib/l10n/app_en.arb` and `app_de.arb`; English is the source.
- Dart lines up to 120 characters (`analysis_options.yaml`), like the Rust side (`rust/rustfmt.toml`).

## Building – what is not obvious

- Rust is pinned in `rust/rust-toolchain.toml`; cargokit is told the same version in `rust/cargokit.yaml`, else it
  builds with whatever toolchain it finds. It runs `rustup run <version> cargo`, and cargo finds `rustc` on `PATH`: a
  Rust of Homebrew before `~/.cargo/bin` has no targets for iOS or Android, and the build fails with "can't find crate
  for `core`". Put `~/.cargo/bin` first.
- The protocols are kernoid's Rust SDK (`kernoid-client`, with `kernoid-e2e`); both come from kernoid's repository by
  commit until they are on crates.io. `rust/src/api/` only translates them for Dart.
- Signing in with OpenID Connect goes through flutter_web_auth_2: `dev.kernoid.kernoid:/oauth` on Apple's systems and
  Android (the `CallbackActivity` in `AndroidManifest.xml`), `http://127.0.0.1:<port>/oauth` on desktops. The system's
  browser is out of the integration test's reach; the protocol is tested in kernoid's SDK against a real kernoid.
- An iOS build needs a `libc` new enough for `backtrace` on iOS – do not set it back below the version in
  `rust/Cargo.lock`.
- Android in CI builds for arm64 only and without debug info; the runner needs disk space freed first.
- `integration_test/app_test.dart` runs the app against a real kernoid – how is in its head. Too many failed logins
  lock an address for some minutes (HTTP 429). On macOS the app's sandbox puts screenshots below
  `~/Library/Containers/dev.kernoid.kernoid/Data/tmp/`.

## Checks

```sh
(cd rust && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings && cargo test --locked && cargo deny check)
dart format --output=none --set-exit-if-changed lib test integration_test && flutter analyze && flutter test
```
