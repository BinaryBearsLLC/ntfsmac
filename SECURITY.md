# Security policy

ntfsmac mounts filesystems through a privileged XPC helper and a pinned Linux microVM. Changes to
the helper, caller validation, mount lifecycle, PF/route state, update checks, or release signing
are security-sensitive.

## Report a vulnerability

Do not open a public issue for a suspected vulnerability. Use this repository's
[private security advisory](../../security/advisories/new) and include:

- affected component and ntfsmac version;
- concise reproduction steps and macOS/Apple Silicon environment;
- expected impact;
- a privacy-reviewed diagnostic excerpt when relevant.

Do not attach drive serials, volume labels, device identifiers, personal paths, credentials, or
unredacted local logs.

## Security boundary

- Device names are validated against `^disk[0-9]+s[0-9]+$` in both the client and helper.
- App-initiated mount, unmount, PF, and route mutations go only through the XPC helper. The app
  never shells out to `sudo`.
- Every active mount owns its security state. Teardown must not flush global PF state, remove a
  default route, or release another mount's resources.
- SECURITY rows consume measured reason-coded evidence and become `unknown` when evidence is
  unavailable or untrusted.
- Diagnostics are local, opt-in exports and omit identifying disk/network/user details.

The v3 compatibility helper uses SMJobBless. macOS may display its technical service label
`com.binarybears.ntfsmac.helper` and a generic executable icon in Full Disk Access; the app names
that exact entry rather than implying it can control System Settings presentation.

## Signing and releases

Contributor and ordinary local builds remain ad-hoc signed. Official BinaryBears releases must be
Developer ID signed, notarized, stapled, Gatekeeper-assessed, and published with a SHA-256 checksum.
Apple credentials live only in Keychain or encrypted GitHub Actions secrets.

The update checker contacts GitHub's public API no more than once every 24 hours, sends no analytics
or device data, ignores drafts/prereleases, and can only open a release page in the user's browser.
