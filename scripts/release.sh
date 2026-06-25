#!/usr/bin/env bash
#
# release.sh — cut a Frost release end-to-end from an already-notarized app.
#
# Run this LOCALLY after you have archived, Developer ID-signed, NOTARIZED, and
# STAPLED frost.app in Xcode and exported it. It does the repeatable parts:
#
#   1. Build the DMG and EdDSA-sign the Sparkle appcast (private key read from
#      your login Keychain — it never leaves this machine).
#   2. Create the GitHub Release for tag v<version> and upload the DMG.
#   3. Deploy the signed appcast to updates.abdeen.dev (Vercel).
#
# Distribution split: the DMG is hosted on GitHub Releases (the appcast's
# <enclosure url> points back at that asset); the appcast itself MUST stay at
# https://updates.abdeen.dev/frost/appcast.xml because Info.plist's SUFeedURL
# hardcodes it. The download PAGE lives in the abdeen.dev repo (src/app/frost),
# is dynamic (reads GitHub at load time), and is deployed with that site — it is
# not touched here.
#
# Usage:
#   scripts/release.sh /path/to/frost.app                 # build, release, deploy
#   DEPLOY=0 scripts/release.sh /path/to/frost.app        # build + release, skip deploy
#
# Prereqs: gh (authenticated), the Sparkle tools publish.sh discovers, and the
# vercel CLI authenticated and `vercel link`ed to the updates.abdeen.dev project.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_SLUG="${REPO_SLUG:-Cuzeth/frost}"
APP_PATH="${APP_PATH:-${1:-$REPO_ROOT/build/export/frost.app}}"

if [ ! -d "$APP_PATH" ]; then
  echo "error: notarized frost.app not found at: $APP_PATH" >&2
  echo "Export a Developer ID-signed, notarized, stapled app from Xcode first," >&2
  echo "then: scripts/release.sh /path/to/frost.app" >&2
  exit 1
fi

# --- Version + tag ----------------------------------------------------------
PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
TAG="v$VERSION"
DMG="$REPO_ROOT/dist/Frost-$VERSION.dmg"
APPCAST="$REPO_ROOT/dist/appcast.xml"

echo "Releasing Frost $VERSION (tag $TAG) to $REPO_SLUG"

# Refuse to overwrite an existing release — bump the version instead.
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  echo "error: release $TAG already exists. Bump MARKETING_VERSION /" >&2
  echo "CURRENT_PROJECT_VERSION, re-export, and retry." >&2
  exit 1
fi

# --- 1. DMG + signed appcast pointing at the GitHub asset -------------------
export DOWNLOAD_URL_PREFIX="https://github.com/$REPO_SLUG/releases/download/$TAG/"
"$REPO_ROOT/scripts/publish.sh" "$APP_PATH"

# --- 2. GitHub Release (uploads the DMG) ------------------------------------
echo "Creating GitHub release $TAG…"
gh release create "$TAG" "$DMG" \
  --repo "$REPO_SLUG" \
  --title "Frost $VERSION" \
  --generate-notes

# --- 3. Deploy the appcast to updates.abdeen.dev (Vercel) -------------------
# A Vercel production deploy REPLACES the project's served files with the deployed
# directory. updates.abdeen.dev is its own Vercel project (separate from the
# abdeen.dev site). Point UPDATES_SITE_DIR at that project's working copy so the
# fresh appcast is added without dropping anything else it serves; the script
# copies it to <dir>/frost/appcast.xml and deploys from there.
SITE_DIR="${UPDATES_SITE_DIR:-$REPO_ROOT/dist/site}"
if [ -z "${UPDATES_SITE_DIR:-}" ]; then
  rm -rf "$SITE_DIR"
  echo "warning: UPDATES_SITE_DIR not set — deploying a Frost-only dir." >&2
  echo "         A prod deploy REPLACES the target project; set UPDATES_SITE_DIR" >&2
  echo "         to your updates.abdeen.dev working copy if it serves anything else." >&2
fi
mkdir -p "$SITE_DIR/frost"
cp "$APPCAST" "$SITE_DIR/frost/appcast.xml"

if [ "${DEPLOY:-1}" = "1" ]; then
  # `vercel link` this dir to the updates.abdeen.dev project once, then deploy.
  ( cd "$SITE_DIR" && vercel deploy --prod --yes )
else
  echo "Appcast written to $SITE_DIR/frost/appcast.xml (DEPLOY=0 — not deployed)."
fi

echo
echo "Done."
echo "  Release: https://github.com/$REPO_SLUG/releases/tag/$TAG"
echo "  Appcast: https://updates.abdeen.dev/frost/appcast.xml"
echo "  Verify:  open the release page, confirm the .dmg downloads, then check an"
echo "           older build sees the update via Check for Updates…"
