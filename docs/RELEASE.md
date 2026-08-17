# BinaryBears release guide

Official releases are built from `dev`, use SemVer beginning at `v3.0.0`, and are published in two
steps: draft artifact first, human validation second.

## Local release candidate

1. Set the same `CFBundleShortVersionString` and `CFBundleVersion` in the app and helper plists.
2. Run the automated suites once on the completed candidate.
3. Build the Developer ID-signed local RC and notarize it.
4. Verify the app/helper identifiers, arm64 architecture, nested signatures, notarization ticket,
   Gatekeeper assessment, DMG contents, and SHA-256.
5. Exercise clean install, old-helper migration, Full Disk Access, a known-clean mount/write/reread/
   unmount, update-check behavior, and complete uninstall.

Do not create a release tag until this candidate passes.

## Signed source tag

Create an SSH-signed tag whose version exactly matches the plist:

```sh
git tag -s v3.0.0 -m "ntfsmac 3.0.0"
git verify-tag v3.0.0
git push origin v3.0.0
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

1. Run **Release notarized DMG** manually from `dev` and enter the version without `v`.
2. The workflow verifies the signed tag and version, runs the release gates, imports credentials
   into a temporary Keychain, builds, signs, notarizes, staples, verifies, and creates a draft.
3. Download `ntfsmac-X.Y.Z-Apple-Silicon.dmg` and its `.sha256` file from that draft.
4. Confirm the checksum, install the downloaded DMG, and run the final smoke test.
5. Publish the existing draft in GitHub. Do not rebuild or replace its files.

Any failure returns to `dev` for a new commit and tag. Never overwrite a published release tag or
artifact.

## GitHub Pages

The static site lives under `site/` and is deployed by the Pages workflow from `dev`. GitHub Pages
must be configured once with **GitHub Actions** as its build source. The site has no analytics and
links to the latest published release, falling back to the Releases page when the API is unavailable.
