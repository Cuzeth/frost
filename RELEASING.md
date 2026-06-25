# Releasing Frost

Two independent trust layers ship a release. Don't conflate them:

- **Apple notarization** — stapled *into* the `.app`/`.dmg`, satisfies Gatekeeper.
  Done locally in Xcode. Lives in the binary, not on any server.
- **Sparkle appcast** — `appcast.xml`, EdDSA-signed with your private key. Hosted
  at the URL hardcoded in `Info.plist` (`SUFeedURL`). This is what lets installed
  copies verify and fetch updates.

## Where things live

| Artifact | Host |
|---|---|
| `Frost-x.y.z.dmg` (notarized) | GitHub Releases (`github.com/Cuzeth/frost`) |
| `appcast.xml` (EdDSA-signed) | `public/frost/appcast.xml` in the **abdeen.dev repo**, served at `updates.abdeen.dev/frost/appcast.xml` |
| Download page | `abdeen.dev/frost` — also in the abdeen.dev repo (`src/app/frost`), reads the latest release from GitHub at load time |

`updates.abdeen.dev` is a **domain alias** of the single abdeen.dev Vercel
project, so the appcast is just a static file in that repo and ships when the site
deploys. The appcast's `<enclosure url>` points back at the GitHub DMG — the DMG
is never uploaded to your domain. The download page doesn't change per release.

## One-time setup

1. **Developer ID Application** certificate in your login Keychain.
2. **Notarization profile**:
   `xcrun notarytool store-credentials "frost-notary" --apple-id <id> --team-id <team> --password <app-specific-pw>`
3. **Sparkle EdDSA key** in your login Keychain. Confirm it matches the app:
   `generate_keys -p` must print `V8xkC2BQlZG91vsCTw7ACPjL1dbRlBKo+ftb9ymNbdM=`.
   If it prints anything else, **stop** — signing with the wrong key breaks
   updates for every installed copy.
4. **`gh auth login`**, and an **abdeen.dev checkout** with push access (the
   release script commits the appcast there; Vercel deploys on push).
5. **Add `updates.abdeen.dev` as a domain** on the abdeen.dev Vercel project
   (Project → Settings → Domains), and point its DNS at Vercel. Both
   `abdeen.dev/frost/appcast.xml` and `updates.abdeen.dev/frost/appcast.xml` then
   serve `public/frost/appcast.xml`. Serving `.xml` as `application/xml` (the
   default) is fine for Sparkle. This is the only piece that makes `SUFeedURL`
   resolve, so do it before the first release.
6. **Download page**: the `abdeen.dev/frost` route (`src/app/frost`). It reads the
   latest release from GitHub, so it doesn't need redeploying per version — it
   ships with the abdeen.dev site.

## Cutting a release

1. **Bump the version** in the Xcode target (both must change; `CURRENT_PROJECT_VERSION`
   must strictly increase — Sparkle compares it):
   - `MARKETING_VERSION` → e.g. `1.0.1` (the display + tag version)
   - `CURRENT_PROJECT_VERSION` → e.g. `2`
2. **Push** `main` so the tag will reference a real remote commit.
3. **Archive → Distribute → Developer ID** in Xcode: sign, notarize, staple,
   export `frost.app`.
4. **Run the release script** (builds the DMG, signs the appcast, creates the
   GitHub release, and commits + pushes the appcast to the abdeen.dev repo so
   Vercel deploys it):
   ```sh
   ABDEEN_DEV_REPO=~/GitHub/abdeen.dev scripts/release.sh /path/to/frost.app
   ```
   `ABDEEN_DEV_REPO` defaults to `../abdeen.dev` (a sibling checkout), so you can
   omit it if the repos sit side by side. Add `DEPLOY=0` to build + create the
   release but only write the appcast into the repo (no commit/push).
5. **Verify**: open the GitHub release, confirm the `.dmg` downloads and opens
   without a Gatekeeper warning, then confirm an older build sees the update via
   *Check for Updates…*.

## What `release.sh` does

Tag is `v$MARKETING_VERSION`. It refuses to overwrite an existing release. It sets
`DOWNLOAD_URL_PREFIX` to the GitHub asset URL and calls `publish.sh` (DMG +
`generate_appcast`), then `gh release create … <dmg>`, then copies the appcast to
`<abdeen.dev>/public/frost/appcast.xml` and commits + pushes **only that file**
(a pathspec commit, so unrelated working changes are never swept in). Apple and
Sparkle private keys stay in your Keychain the whole time.
