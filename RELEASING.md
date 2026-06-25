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
| `appcast.xml` (EdDSA-signed) | `updates.abdeen.dev/frost/appcast.xml` (Vercel) |
| Download page | `abdeen.dev/frost` — lives in the abdeen.dev repo at `src/app/frost`, reads the latest release from GitHub at load time |

The appcast's `<enclosure url>` points back at the GitHub DMG. The DMG is never
uploaded to your domain. The download page is part of the abdeen.dev site and
deploys with it (Vercel git push); it does not change per release.

## One-time setup

1. **Developer ID Application** certificate in your login Keychain.
2. **Notarization profile**:
   `xcrun notarytool store-credentials "frost-notary" --apple-id <id> --team-id <team> --password <app-specific-pw>`
3. **Sparkle EdDSA key** in your login Keychain. Confirm it matches the app:
   `generate_keys -p` must print `V8xkC2BQlZG91vsCTw7ACPjL1dbRlBKo+ftb9ymNbdM=`.
   If it prints anything else, **stop** — signing with the wrong key breaks
   updates for every installed copy.
4. **CLIs**: `gh auth login`, and `vercel login` with the CLI `vercel link`ed to
   the `updates.abdeen.dev` project.
5. **Download page**: it's the `abdeen.dev/frost` route in the abdeen.dev repo
   (`src/app/frost`). It reads the latest release from GitHub, so once it's live
   it doesn't need redeploying per version — it ships with the abdeen.dev site.

### `updates.abdeen.dev` hosting note

It must serve `frost/appcast.xml`. This is a Vercel project bound to the
`updates.abdeen.dev` domain, separate from the abdeen.dev site. Serving `.xml` as
`application/xml` (the default) is fine for Sparkle.

**A production deploy replaces the project's served files with the deployed
directory.** So point `UPDATES_SITE_DIR` at that project's working copy — the
script copies the fresh `appcast.xml` into `<dir>/frost/` and deploys the whole
dir, preserving anything else it serves:

```sh
UPDATES_SITE_DIR=~/sites/updates.abdeen.dev scripts/release.sh /path/to/frost.app
```

Without `UPDATES_SITE_DIR`, it deploys a Frost-only dir (just `frost/appcast.xml`)
and warns — only safe if `updates.abdeen.dev` is dedicated to Frost.

## Cutting a release

1. **Bump the version** in the Xcode target (both must change; `CURRENT_PROJECT_VERSION`
   must strictly increase — Sparkle compares it):
   - `MARKETING_VERSION` → e.g. `1.0.1` (the display + tag version)
   - `CURRENT_PROJECT_VERSION` → e.g. `2`
2. **Push** `main` so the tag will reference a real remote commit.
3. **Archive → Distribute → Developer ID** in Xcode: sign, notarize, staple,
   export `frost.app`.
4. **Run the release script** (it builds the DMG, signs the appcast, creates the
   GitHub release, and deploys the appcast to Vercel):
   ```sh
   UPDATES_SITE_DIR=~/sites/updates.abdeen.dev scripts/release.sh /path/to/frost.app
   ```
   Add `DEPLOY=0` to build + create the release but skip the Vercel deploy (the
   appcast is written under the staged dir for you to deploy by hand).
5. **Verify**: open the GitHub release, confirm the `.dmg` downloads and opens
   without a Gatekeeper warning, then confirm an older build sees the update via
   *Check for Updates…*.

## What `release.sh` does

Tag is `v$MARKETING_VERSION`. It refuses to overwrite an existing release. It sets
`DOWNLOAD_URL_PREFIX` to the GitHub asset URL and calls `publish.sh` (DMG +
`generate_appcast`), then `gh release create … <dmg>`, then deploys the appcast.
Apple and Sparkle private keys stay in your Keychain the whole time.
