#!/bin/sh
# SPDX-License-Identifier: MIT
# Builds rust/ as a static library for the File Provider extension – a build phase of the extension's target in
# macos/ and ios/, before its sources. The extension links the library (OTHER_LDFLAGS) and calls the core of the file
# shells through its two C functions (rust/src/provider.rs, native/apple/CoreC/).
#
# The target comes from KERNOID_RUST_TARGET (FileProvider.xcconfig); the Rust version from rust/rust-toolchain.toml.
# Always optimised: the extension runs within a tight memory limit on iOS. Built in the project's temporary folder,
# apart from cargokit's build of the same crate for the app.
set -eu

: "${KERNOID_RUST_TARGET:?KERNOID_RUST_TARGET is not set}"
here=$(cd "$(dirname "$0")" && pwd -P)
crate="$here/../../rust"

# Rust from rustup first – a Rust of Homebrew has no targets for iOS (CLAUDE.md, Building) –, and Xcode's own tools
# out of the way of the build scripts, as cargokit does (rust_builder/cargokit/build_pod.sh).
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'Contents/Developer/' | tr '\n' ':')
export PATH="$HOME/.cargo/bin:${PATH%:}"

export CARGO_TARGET_DIR="${PROJECT_TEMP_DIR:?}/kernoid-rust"
cd "$crate"
rustup target add "$KERNOID_RUST_TARGET" >/dev/null 2>&1 || true
cargo rustc --release --lib --target "$KERNOID_RUST_TARGET" --crate-type staticlib
