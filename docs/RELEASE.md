# BinaryBears release guide

Official releases come from `dev` and ship two Apple Silicon installers by default:

- Standard: `SMAppService` helper for macOS 13+.
- Legacy: explicitly labelled `SMJobBless` compatibility build.

GitHub Actions creates a draft. Publish only that tested draft; never rebuild or replace its files.

## 1. Local release gate

Before tagging:

1. Keep `CFBundleShortVersionString` and `CFBundleVersion` identical in the app and both helper
   plists.
2. Run the shell suite plus the complete Standard and Legacy Swift suites.
3. Build both DMGs with the official BinaryBears artwork and Developer ID identity.
4. Verify architecture, nested signatures, version, checksums, DMG contents, visible app name,
   helper variant, and mounted-Finder layout.
5. Exercise the changed behavior and a known-clean install/mount/write/reread/unmount cycle on the
   Standard build. Repeat the applicable install, mount, and uninstall checks on Legacy.

Do not tag a candidate that has not passed these checks. Contributor builds may remain ad-hoc;
official artifacts must be Developer ID signed, notarized, stapled, and Gatekeeper accepted.

## 2. Signed source tag

Run from the exact `dev` commit that passed the gate:

```sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' gui/Info.plist)"
git tag -s "v${VERSION}" -m "ntfsmac ${VERSION}"
git verify-tag "v${VERSION}"
git push origin dev "v${VERSION}"
```

The signed tag must point to the current `origin/dev` commit. Pushing it does not publish a release.

## 3. Build the draft

Run **Release notarized DMG** from `dev`, enter the version without `v`, and keep Legacy enabled.
The workflow:

- verifies the signed tag and matching plist versions;
- reruns all source and test gates;
- imports release credentials into a temporary Keychain;
- builds, signs, notarizes, staples, and verifies both DMGs;
- creates one draft release with both DMGs and both `.sha256` files.

Credentials stay in Keychain or encrypted GitHub Actions secrets and never enter Git.

## 4. Validate and publish

Download the four draft assets and confirm:

- each checksum matches its DMG;
- both mounted DMGs contain an app named exactly `ntfsmac.app`;
- signatures, stapling, and Gatekeeper pass on the downloaded files;
- the changed behavior and a short Standard/Legacy smoke test pass.

Publish the existing draft and verify the public release page, assets, latest-release endpoint,
update checker, CI, and Pages links. If any gate fails, fix `dev` and create a new commit/tag; never
overwrite a published tag or artifact.

Only approved artwork belongs in `build/dmg-assets/`. Historical validation detail belongs in the
dated files under `docs/testing/`, not in this operating guide.
