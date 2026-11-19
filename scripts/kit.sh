#!/bin/sh
# SPDX-License-Identifier: MIT
# Builds the app against a checkout of kernoid/kernoid beside this one (or KERNOID_DIR) instead of the release in
# pubspec.yaml: writes pubspec_overrides.yaml – not tracked – naming every package of the kit by path. CI does the same
# with the checkout of KERNOID_REF. Remove the file to go back to the release (and never commit a pubspec.lock made
# with it).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
kernoid=$(cd "${KERNOID_DIR:-$here/../kernoid}" && pwd)
kit="$kernoid/kit/flutter"
[ -d "$kit/kernoid_shell" ] || { echo "no kit at $kit" >&2; exit 1; }
{
  echo "# Written by scripts/kit.sh – the kit of $kit, not the release."
  echo "dependency_overrides:"
  for package in "$kit"/kernoid_*; do
    name=$(basename "$package")
    printf '  %s:\n    path: %s\n' "$name" "$package"
  done
} >"$here/pubspec_overrides.yaml"
echo "pubspec_overrides.yaml: the kit of $kit"
