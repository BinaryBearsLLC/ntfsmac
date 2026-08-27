# BinaryBears release guide

Official releases are built from `dev`, use SemVer beginning at `v3.0.0`, and are published in two
steps: draft artifacts first, human validation second. GUI releases produce the standard
SMAppService DMG and the explicitly labelled Legacy SMJobBless DMG by default.

## v3.1.0 DMG branding

The v3.1.0 standard and Legacy DMGs use the official BinaryBears logo assets supplied by the
maintainer. Do not substitute generated, traced, redrawn, placeholder, or otherwise unapproved
marks. Both installers share the approved brand system; the visible app remains `ntfsmac`, and
only the compatibility artifact is labelled `Legacy`.

After the assets are integrated, inspect both mounted DMGs at their actual Finder size and confirm
logo clarity, spacing, drag direction, app/Applications alignment, and naming before continuing to
the local release candidate. Automated image/layout/signature checks supplement but do not replace
that visual approval.

Only release-required installer artwork belongs in `build/dmg-assets/`. Design experiments and
local DMG-interface testers stay outside the tracked tree.

## Local release candidate

1. Set the same `CFBundleShortVersionString` and `CFBundleVersion` in the app, standard-helper, and
   Legacy-helper plists.
2. Run the automated suites for both helper variants on the completed candidate.
3. Build both Developer ID-signed local RCs and notarize them.
4. Verify each app/helper identity, arm64 architecture, nested signatures, notarization ticket,
   Gatekeeper assessment, DMG contents, visible app name, and SHA-256.
5. On the standard artifact, exercise clean registration, Login Items approval and denial,
   Legacy-to-standard migration, mismatch repair, Full Disk Access, a known-clean mount/write/
   reread/unmount, update-check behavior, and complete uninstall. For the positive update path,
   install a temporary locally re-signed copy whose displayed version is lower than the current
   public stable release; verify that Settings opens that exact release, then remove the fixture.
   Never commit or upload the synthetic old build.
6. Repeat the applicable clean install, mount, and uninstall checks on the Legacy artifact.

Do not create a release tag until this candidate passes.

## Signed source tag

Create an SSH-signed tag whose version exactly matches the plist:

```sh
git tag -s v3.1.0 -m "ntfsmac 3.1.0"
git verify-tag v3.1.0
git push origin v3.1.0
```

The tag must be reachable from `origin/dev`. Pushing it does not publish a release.

## GitHub secrets

Configure these repository Actions secrets, matching the working USB-Bench release setup:

| Secret | Purpose |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 Developer ID certificate and private key export |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` export |
| `APPLE_SIGNING_IDENTITY` | Full Developer ID Application identity |
| `APPLE_API_KEY_BASE64` | Base64 App Store Connect `.p8` key |
| `APPLE_API_KEY_ID` | App Store Connect key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |

Never commit certificate files, API keys, passwords, Keychain profiles, or encoded secret values.

## Draft and publish

1. Run **Release notarized DMG** manually from `dev`, enter the version without `v`, and leave
   **include legacy** enabled for the normal dual release. Disable it only after an explicit product
   decision; the local builder has the equivalent `--no-legacy` control.
2. The workflow verifies the signed tag and version, runs the release gates, imports credentials
   into a temporary Keychain, builds, signs, notarizes, staples, verifies, and creates a draft.
3. Download both `ntfsmac-X.Y.Z-Apple-Silicon.dmg` and
   `ntfsmac-X.Y.Z-Legacy-Apple-Silicon.dmg`, together with both `.sha256` files, from that draft.
4. Confirm both checksums, confirm both DMGs contain an app named exactly `ntfsmac.app`, and run
   the final smoke matrix for both variants.
5. Publish the existing draft in GitHub. Do not rebuild or replace its files.

Any failure returns to `dev` for a new commit and tag. Never overwrite a published release tag or
artifact.

## GitHub Pages

The static site lives under `site/` and is deployed by the Pages workflow from `dev`. GitHub Pages
must be configured once with **GitHub Actions** as its build source. The site has no analytics and
links to the latest published release, falling back to the Releases page when the API is unavailable.
