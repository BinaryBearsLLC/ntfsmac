# Contributing

## Before you start

Start with the canonical
[`BinaryBears roadmap`](docs/BINARYBEARS_ROADMAP.md) and
[`branch workflow`](docs/BRANCHING.md), then read
[`docs/dev/PLAN.md`](docs/dev/PLAN.md) for the historical architecture/build plan and, for GUI
work, [`docs/dev/GUI-PLAN.md`](docs/dev/GUI-PLAN.md) for the current behavior contract.
[`CLAUDE.md`](CLAUDE.md) /
[`AGENTS.md`](AGENTS.md) has the non-negotiables (driver default, transport, signing, privilege
boundary) — don't re-litigate those in a PR without discussion first.

## Setup

- Apple Silicon Mac, macOS 13.0+. No Intel fallback is supported or planned.
- Clone with submodules: `git clone --recurse-submodules <repo-url>` (or
  `git submodule update --init` after a plain clone — `vendor/src/anylinuxfs` is a
  submodule).
- CLI build/install: `./install.sh` (refuses non-arm64, ad-hoc signs, strips quarantine
  xattrs).
- GUI build: `swift build` via `Package.swift`, or open in Xcode.
- Interactive release build: double-click `build.command`, or run
  `./build.command [cli|gui|both]`. It reuses the repository's existing build scripts and
  writes verified CLI and/or GUI artifacts under `dist/`; it does not install them. Missing
  command-line dependencies are offered for installation only after explicit confirmation;
  full Xcode remains an Apple/App Store installation.

## Testing

- Manual test guide (real hardware, outside a sandboxed agent environment):
  [`docs/dev/TESTING.md`](docs/dev/TESTING.md).
- Automated: `.github/workflows/ci.yml` runs on push/PR.

## Making changes

- Keep the CLI and GUI in sync with `PLAN.md`/`docs/dev/GUI-PLAN.md` — if a change drifts from what
  those docs specify, update the doc in the same PR, don't silently diverge.
- Update roadmap status only when the implementation and its stated evidence are both present.
  A lower-layer primitive or passing unit test is not automatically a shipped user-facing feature.
- Every mount/unmount/pf/route control change must keep going through the SMJobBless XPC
  helper — see [`SECURITY.md`](SECURITY.md).
- Device identifiers must stay validated against `^disk[0-9]+s[0-9]+$` in both CLI and
  GUI/helper before any shell invocation.

## Pull requests

- Conventional commit-style messages (`feat:`, `fix:`, `refactor:`, …).
- Pull requests for BinaryBears roadmap work start from and target `BinaryBearsLLC/ntfsmac:dev`.
  The fork's `main` intentionally mirrors current upstream. Upstream
  submissions to `khr898/ntfsmac` are a separate maintainer decision and should preserve upstream
  scope and attribution.
- Keep one roadmap deliverable per focused branch/PR; include documentation and test evidence in
  that same review unit.
- Note which `PLAN.md`/`docs/dev/GUI-PLAN.md` unit(s) the change addresses, if any.
- Security-sensitive changes (XPC helper, privilege boundary, pf/route handling) should call
  that out explicitly in the PR description.
