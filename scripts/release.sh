#!/usr/bin/env bash
# Build FormatC as a universal Release binary and package it as a signed-adhoc
# .zip ready to attach to a GitHub Release.
#
# Why the CLI ARCHS override: xcodebuild honors the target's ARCHS setting most
# of the time, but there are ways to invoke it (with -destination, from IDE-
# spawned processes) where it silently narrows to the host arch. Setting the
# override on the command line makes the universal build unconditional.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Build OUTSIDE the repo dir. If the repo lives under ~/Desktop or ~/Documents
# with iCloud Drive sync, macOS tags every file with com.apple.FinderInfo the
# moment it's written, and codesign rejects the bundle ("resource fork, Finder
# information, or similar detritus not allowed"). Building in /tmp sidesteps it.
BUILD=${BUILD:-"/tmp/formatc-release-build"}
OUT=${OUT:-"$ROOT/dist/FormatC.zip"}

rm -rf "$BUILD" "$OUT"
mkdir -p "$BUILD" "$(dirname "$OUT")"

# Clear provenance xattrs that Finder / Preview add to source files and that
# hardened-runtime codesign later rejects.
xattr -rc "$ROOT/app/FormatC" 2>/dev/null || true

xcodebuild \
  -project "$ROOT/app/FormatC.xcodeproj" \
  -scheme FormatC -configuration Release \
  -derivedDataPath "$BUILD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build

APP="$BUILD/Build/Products/Release/FormatC.app"
echo
echo "Built:"
lipo -info "$APP/Contents/MacOS/FormatC"

# ditto is Apple's blessed way to zip an .app — preserves symlinks, resource
# forks, and the code signature. A plain `zip` mangles bundles.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
echo
echo "Packaged: $OUT ($(du -h "$OUT" | cut -f1))"
