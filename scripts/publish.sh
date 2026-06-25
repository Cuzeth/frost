#!/usr/bin/env bash
#
# publish.sh — package a Frost release and (re)generate the Sparkle appcast.
#
# This does NOT build or sign the app. In Xcode: archive, sign with Developer ID
# + Hardened Runtime, notarize, and staple the .app FIRST, then point this
# script at the exported frost.app.
#
# Pipeline:
#   1. Read the version from the .app's Info.plist.
#   2. Stage the .app (+ an /Applications symlink) and build a compressed DMG.
#   3. Run Sparkle's generate_appcast over the output dir — it signs the DMG
#      with the EdDSA private key (read from the login Keychain) and writes
#      appcast.xml.
#
# Then upload BOTH dist/Frost-<version>.dmg and dist/appcast.xml to:
#   https://updates.abdeen.dev/frost/
#
# Usage:
#   scripts/publish.sh [path/to/frost.app]
#
# Environment overrides:
#   APP_PATH      Path to the exported frost.app (alternative to the argument).
#   SPARKLE_BIN   Dir containing generate_appcast (auto-discovered otherwise).

set -euo pipefail

# --- Config -----------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
DOWNLOAD_URL_PREFIX="https://updates.abdeen.dev/frost/"
APP_PATH="${APP_PATH:-${1:-$REPO_ROOT/build/export/frost.app}}"

# --- Locate the exported .app ----------------------------------------------
if [ ! -d "$APP_PATH" ]; then
  echo "error: frost.app not found at: $APP_PATH" >&2
  echo "Export it from Xcode first, or pass its path:" >&2
  echo "  scripts/publish.sh /path/to/frost.app" >&2
  exit 1
fi

# --- Locate Sparkle's generate_appcast -------------------------------------
# The path under DerivedData contains a per-project hash, so discover it rather
# than hardcoding. Search is scoped to this user's DerivedData only.
find_sparkle_bin() {
  if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "$SPARKLE_BIN"
    return 0
  fi
  local derived="$HOME/Library/Developer/Xcode/DerivedData"
  local hit
  hit="$(/usr/bin/find "$derived" -type f -name generate_appcast \
        -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' 2>/dev/null \
        | head -n 1)"
  if [ -n "$hit" ]; then
    dirname "$hit"
    return 0
  fi
  return 1
}

SPARKLE_BIN="$(find_sparkle_bin || true)"
if [ -z "${SPARKLE_BIN:-}" ] || [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "error: could not find Sparkle's generate_appcast." >&2
  echo "Set SPARKLE_BIN to the dir containing it, e.g.:" >&2
  echo "  export SPARKLE_BIN=~/Library/Developer/Xcode/DerivedData/frost-*/SourcePackages/artifacts/sparkle/Sparkle/bin" >&2
  exit 1
fi
echo "Using Sparkle tools: $SPARKLE_BIN"

# --- Read version from the app ---------------------------------------------
PLIST="$APP_PATH/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
echo "Packaging Frost $SHORT_VERSION (build $BUILD_VERSION)"

# --- Build the DMG ----------------------------------------------------------
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/Frost-$SHORT_VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Frost $SHORT_VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"
echo "Built DMG: $DMG_PATH"

# --- Generate / update the appcast -----------------------------------------
# generate_appcast scans DIST_DIR for archives, signs each with the EdDSA
# private key from the login Keychain (created by `generate_keys`), and writes
# appcast.xml with enclosure URLs prefixed by DOWNLOAD_URL_PREFIX.
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  -o "$DIST_DIR/appcast.xml" \
  "$DIST_DIR"

echo
echo "Done."
echo "  DMG:     $DMG_PATH"
echo "  Appcast: $DIST_DIR/appcast.xml"
echo
echo "Next: upload BOTH files to ${DOWNLOAD_URL_PREFIX}"
echo "(If generate_appcast reported a missing key, run Sparkle's generate_keys"
echo " once — it stores the private key in your login Keychain.)"
