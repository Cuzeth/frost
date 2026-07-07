#!/usr/bin/env bash
#
# changelog.sh — print one version's release notes from CHANGELOG.md.
#
# Extracts the Markdown body between the "## [<version>] - <date>" heading and
# the next "## " heading (or the link-reference block at the end of the file).
# The heading line itself is omitted, so the output is ready to drop straight
# into a GitHub release (`gh release create --notes-file`) or next to a DMG as a
# Sparkle release-notes file (Frost-<version>.md, embedded by generate_appcast).
#
# Usage:
#   scripts/changelog.sh <version> [path/to/CHANGELOG.md]
#
# Prints the section body to stdout. Exits non-zero (and prints nothing) if the
# changelog is missing or has no section for <version>, so callers can fall back.

set -euo pipefail

VERSION="${1:?usage: changelog.sh <version> [changelog-path]}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="${2:-$REPO_ROOT/CHANGELOG.md}"

if [ ! -f "$CHANGELOG" ]; then
  echo "changelog.sh: no changelog at $CHANGELOG" >&2
  exit 1
fi

# Capture the section body. Start printing on the line after "## [<version>]",
# stop at the next "## " heading or the "[label]: url" link-reference tail.
body="$(
  awk -v ver="$VERSION" '
    /^## / {
      tok = ""
      if (match($0, /\[[^]]*\]/)) tok = substr($0, RSTART + 1, RLENGTH - 2)
      if (tok == ver) { grab = 1; next }
      if (grab) exit
      next
    }
    grab && /^\[[^]]+\]:[[:space:]]/ { exit }
    grab { print }
  ' "$CHANGELOG"
)"

# Strip HTML comments (e.g. the maintenance hint under [Unreleased]). They never
# render in GitHub or Sparkle, so they must not reach the raw notes if one is
# ever left inside a shipped section. Handles comments spanning multiple lines.
body="$(printf '%s\n' "$body" | awk '
  {
    line = $0; out = ""
    while (1) {
      if (incomment) {
        i = index(line, "-->")
        if (i == 0) { line = ""; break }
        line = substr(line, i + 3); incomment = 0
      } else {
        i = index(line, "<!--")
        if (i == 0) { out = out line; break }
        out = out substr(line, 1, i - 1); line = substr(line, i + 4); incomment = 1
      }
    }
    print out
  }
')"

# Trim leading and trailing blank lines so the notes start at the first bullet.
# Done in awk for portability (BSD/macOS sed lacks a clean trailing-blank trim).
body="$(printf '%s\n' "$body" | awk '
  { line[NR] = $0 }
  NF { if (!first) first = NR; last = NR }
  END { if (last) for (i = first; i <= last; i++) print line[i] }
')"

if [ -z "$body" ]; then
  echo "changelog.sh: no release notes for version $VERSION in $CHANGELOG" >&2
  exit 1
fi

printf '%s\n' "$body"
