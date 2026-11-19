#!/bin/sh
# SPDX-License-Identifier: MIT
# Builds the Rust side – the crate in the kit's package kernoid_bridge (rust/) – as a static library for the File
# Provider extension: a build phase of the extension's target in macos/ and ios/, before its sources. The extension
# links the library (OTHER_LDFLAGS) and calls the core of the file shells through its two C functions
# (rust/src/provider.rs there, native/apple/CoreC/ here). Where the package is comes from .dart_tool/package_config.json.
#
# The target comes from KERNOID_RUST_TARGET (FileProvider.xcconfig); the Rust version from the crate's rust-toolchain.toml.
# Always optimised: the extension runs within a tight memory limit on iOS. Built in the project's temporary folder,
# apart from cargokit's build of the same crate for the app.
set -eu

: "${KERNOID_RUST_TARGET:?KERNOID_RUST_TARGET is not set}"
here=$(cd "$(dirname "$0")" && pwd -P)
config="$here/../../.dart_tool/package_config.json"
crate=$(/usr/bin/python3 -c '
import json, sys, urllib.parse, os
config = sys.argv[1]
root = next(p["rootUri"] for p in json.load(open(config))["packages"] if p["name"] == "kernoid_bridge")
path = urllib.parse.urlparse(root).path if root.startswith("file:") else os.path.join(os.path.dirname(config), root)
print(os.path.normpath(os.path.join(path, "rust")))
' "$config")

# Rust from rustup first – a Rust of Homebrew has no targets for iOS (CLAUDE.md, Building) –, and Xcode's own tools
# out of the way of the build scripts, as cargokit does (cargokit/build_pod.sh in kernoid_bridge).
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'Contents/Developer/' | tr '\n' ':')
export PATH="$HOME/.cargo/bin:${PATH%:}"

export CARGO_TARGET_DIR="${PROJECT_TEMP_DIR:?}/kernoid-rust"
cd "$crate"
rustup target add "$KERNOID_RUST_TARGET" >/dev/null 2>&1 || true
cargo rustc --release --lib --target "$KERNOID_RUST_TARGET" --crate-type staticlib
