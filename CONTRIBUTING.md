# Contributing

Focused fixes and improvements are welcome. No contributor license agreement is required.

## Before starting

Read the short [roadmap](docs/BINARYBEARS_ROADMAP.md), [branch policy](docs/BRANCHING.md), and the
non-negotiables in [CLAUDE.md](CLAUDE.md). The current GUI contract is
[docs/dev/GUI-PLAN.md](docs/dev/GUI-PLAN.md); `docs/dev/PLAN.md` is the historical build plan.

Important invariants:

- The 3.1.3 candidate targets Apple Silicon and macOS 14+; older-OS execution must
  be validated separately from a successful build.
- `ntfs-3g` remains the default; NTFS3 is explicit and experimental.
- NFS over the private vmnet link; no SMB or loopback design.
- NFS remains `soft` for hot-unplug safety.
- Privileged UI operations use the XPC helper, never raw `sudo`.
- Partition identifiers are validated before every shell boundary.

## Setup and tests

```sh
git clone --recurse-submodules https://github.com/BinaryBearsLLC/ntfsmac.git
cd ntfsmac
git switch dev
swift build
swift test
tests/run-all.sh
```

`./build.command` creates local artifacts under `dist/`. A 3.1.3 GUI build produces only
the Standard SMAppService distribution. Legacy source remains for migration tests;
`--no-legacy` is now a compatibility no-op. Builds are ad-hoc unless the exact official
BinaryBears Developer ID identity is available; `SIGNING_IDENTITY=-` forces ad-hoc mode.
Contributors do not need or receive BinaryBears signing/notarization credentials.

Use the manual hardware guide only when the change touches packaging, helper lifecycle, mounts, or
real device behavior: [docs/dev/TESTING.md](docs/dev/TESTING.md).

## Pull requests

- Branch from and target `dev` for BinaryBears work.
- Keep one coherent outcome per pull request and use conventional commit prefixes.
- Explain user-visible behavior, security-boundary impact, and exact validation performed.
- Update status documents only when the implementation and stated evidence both exist.
- Never commit build output, local evidence folders, private device data, credentials, personal
  filesystem paths, or generated diagnostic logs.

Upstream proposals use a clean branch rooted at `upstream/main`; they are a separate maintainer
decision and must exclude BinaryBears-only branding and roadmap work.
