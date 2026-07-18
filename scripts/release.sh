#!/usr/bin/env bash
# Build Format as a universal Release binary, sign it with your Developer ID
# certificate, submit it to Apple's notary service, staple the ticket, and
# package the notarized bundle as a .zip ready to attach to a GitHub Release.
#
# If no "Developer ID Application" cert is found in the Keychain, the script
# gracefully degrades to ad-hoc signing + no notarization. The bundle still
# works locally, but downloaders will see the Gatekeeper dialog. See
# docs/notarize.md for the one-time cert + credential setup.
#
# Environment overrides:
#   CODESIGN_IDENTITY  full name of the cert ("Developer ID Application: …")
#   NOTARY_PROFILE     keychain profile name (default: formatc-notary)
#   SKIP_NOTARIZE      set to 1 to build + sign but not submit to Apple
#   BUILD              build derived-data path (default: /tmp/…)
#   OUT                output zip path (default: dist/Format.zip)

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Build OUTSIDE the repo dir. If the repo lives under ~/Desktop or ~/Documents
# with iCloud Drive sync, macOS tags every file with com.apple.FinderInfo the
# moment it's written, and codesign rejects the bundle ("resource fork, Finder
# information, or similar detritus not allowed"). Building in /tmp sidesteps it.
BUILD=${BUILD:-"/tmp/formatc-release-build"}
OUT=${OUT:-"$ROOT/dist/Format.zip"}
NOTARY_PROFILE=${NOTARY_PROFILE:-formatc-notary}
SKIP_NOTARIZE=${SKIP_NOTARIZE:-0}

# ── Detect signing identity ─────────────────────────────────────────────
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:-}
if [ -z "$CODESIGN_IDENTITY" ]; then
    # `security find-identity` output shape:
    #   1) ABCDEF... "Developer ID Application: Full Name (TEAMID)"
    CODESIGN_IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}'
    ) || true
fi

TEAM_ID=""
if [ -n "$CODESIGN_IDENTITY" ]; then
    TEAM_ID=$(sed -n 's/.*(\([A-Z0-9]*\))$/\1/p' <<<"$CODESIGN_IDENTITY" || true)
    echo "Signing with: $CODESIGN_IDENTITY"
    [ -n "$TEAM_ID" ] && echo "Team ID:      $TEAM_ID"
else
    echo "⚠️  No 'Developer ID Application' cert found — falling back to ad-hoc."
    echo "   See docs/notarize.md to set one up. Skipping notarization."
    SKIP_NOTARIZE=1
fi

# ── Prepare paths ───────────────────────────────────────────────────────
rm -rf "$BUILD" "$OUT"
mkdir -p "$BUILD" "$(dirname "$OUT")"

# Clear provenance xattrs on source files that hardened runtime later rejects.
xattr -rc "$ROOT/app/FormatC" 2>/dev/null || true

# ── Build ───────────────────────────────────────────────────────────────
XCODEBUILD_ARGS=(
    -project "$ROOT/app/FormatC.xcodeproj"
    -scheme FormatC -configuration Release
    -derivedDataPath "$BUILD"
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
)
if [ -n "$CODESIGN_IDENTITY" ]; then
    XCODEBUILD_ARGS+=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY"
        DEVELOPMENT_TEAM="$TEAM_ID"
        OTHER_CODE_SIGN_FLAGS='--timestamp'
    )
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" build

# PRODUCT_NAME is "Format" (the target/scheme stay FormatC internally).
APP="$BUILD/Build/Products/Release/Format.app"
echo
echo "Built:"
lipo -info "$APP/Contents/MacOS/Format"

# ── Verify signature ────────────────────────────────────────────────────
echo
echo "Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

# ── Package for notary submission ───────────────────────────────────────
# ditto is Apple's blessed way to zip an .app — preserves symlinks, resource
# forks, and the code signature. A plain `zip` mangles bundles.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

# ── Notarize + staple ───────────────────────────────────────────────────
if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo
    echo "Packaged (unsigned or ad-hoc, not notarized): $OUT"
    exit 0
fi

echo
echo "Submitting to Apple notary service (usually 30–120s)…"
if ! xcrun notarytool submit "$OUT" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait 2>&1 | tee /tmp/formatc-notarize.log; then
    echo "❌ Notarization failed."
    echo "   Inspect: xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
    exit 1
fi

if ! grep -q "status: Accepted" /tmp/formatc-notarize.log; then
    echo "❌ Notarization did not return Accepted."
    SUBMISSION_ID=$(grep -m1 "id:" /tmp/formatc-notarize.log | awk '{print $2}')
    [ -n "$SUBMISSION_ID" ] && \
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE"
    exit 1
fi

echo
echo "Stapling ticket into bundle…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Repackage with the staple ticket inside.
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

echo
echo "✓ Notarized and stapled: $OUT ($(du -h "$OUT" | cut -f1))"
