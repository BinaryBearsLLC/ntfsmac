# BinaryBears release guide

The 3.1.3 release line targets Apple Silicon on macOS 14+ and ships one Standard
installer using `SMAppService`. Legacy distribution is deprecated; the `3.1.2`
branch preserves the earlier source line. Legacy helper code remains for migration
and regression testing, not as a second 3.1.3 release artifact.

Work on `Update/3.1.3` until the candidate passes validation. Only then, with maintainer
approval, integrate it into `dev` and use the official release workflow. The deployment
target alone does not prove Sonoma compatibility; consult the
[local Sonoma validation record](testing/SONOMA_LOCAL_VALIDATION_2026-09-08.md).

GitHub Actions creates a draft. Publish only that tested draft; never rebuild or replace its files.

## Beta channel

The owner has approved a separate 3.1.3 beta channel. It does not promote 3.1.3 to
stable or move `dev`. Use a signed `v3.1.3-beta.N` tag at the exact published
`Update/3.1.3` commit and dispatch the release workflow from that branch.

Keep Apple's version keys numeric and equal across app/helpers. The app's
`NTFSMACReleaseTag` identifies the public version; `NTFSMACReleaseLabel` displays
`Beta N`. `build/lib/release-version.sh` rejects mismatched versions and labels.
The workflow marks beta drafts as prereleases and explicitly not latest.

Beta packaging still requires source tests, Developer ID signing, notarization,
stapling and validation of the actual distributed files. Record incomplete hardware
coverage in the beta notes; it is not a stable compatibility claim. Before publishing,
complete the available current-host driver checks and verify diagnostic export and
the changed UI. Native Sonoma qualification remains a stable-release gate.

The site keeps the stable download on GitHub's latest-release endpoint and discovers
public beta releases separately. Drafts never produce download buttons. The app's
normal updater remains stable-only; a beta may offer the stable version with the same
numeric version once available. Never publish a beta as the latest stable release.

## 1. Local release gate

Before tagging a stable release (beta-specific scope is above):

1. Keep `CFBundleShortVersionString` and `CFBundleVersion` identical in the app and both helper
   plists.
2. Run the shell suite plus the complete Standard and Legacy Swift suites.
3. Build the Standard DMG with the official BinaryBears artwork and Developer ID identity.
4. Verify architecture, nested signatures, version, checksums, DMG contents, visible app name,
   helper variant, and mounted-Finder layout.
5. Exercise the changed behavior and a known-clean install/mount/write/reread/unmount cycle on the
   Standard build on macOS 14 and the current macOS. Exercise every advertised driver
   (NTFS through ntfs-3g, ext2, ext3, ext4) and mixed NTFS/non-NTFS detection separately.
6. Verify migration from an installed Legacy helper to Standard, including uninstall.
   Test newer-OS optimizations on the OS that enables them. Record native hardware,
   guest execution, and nested-virtualization results separately; a GUI-only VM test
   is not driver acceptance.

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

Run **Release notarized DMG** from `dev` and enter the version without `v`.
The workflow:

- verifies the signed tag and matching plist versions;
- reruns all source and test gates;
- imports release credentials into a temporary Keychain;
- builds, signs, notarizes, staples, and verifies the Standard DMG;
- creates one draft release with that DMG and its `.sha256` file.

No Legacy asset is selected, even if older artifacts remain in `dist/`. The obsolete
`INCLUDE_LEGACY=true` option fails before build or credential access.

Credentials stay in Keychain or encrypted GitHub Actions secrets and never enter Git.

## 4. Validate and publish

Download the two draft assets and confirm:

- each checksum matches its DMG;
- the mounted DMG contains an app named exactly `ntfsmac.app`;
- signatures, stapling, and Gatekeeper pass on the downloaded files;
- the changed behavior and a Standard smoke test pass.

Publish the existing draft and verify the public release page, assets, latest-release endpoint,
update checker, CI, and Pages links. If any gate fails, fix `dev` and create a new commit/tag; never
overwrite a published tag or artifact.

Only approved artwork belongs in `build/dmg-assets/`. Historical validation detail belongs in the
dated files under `docs/testing/`, not in this operating guide.
