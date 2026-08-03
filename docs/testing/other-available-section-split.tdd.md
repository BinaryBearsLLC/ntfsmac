# TDD Evidence — "Other available" section split (idle vs mounted)

**Source plan:** inline `/ecc:plan` output (this session), not a `*.plan.md` file.
**Branch:** `feat/ntfs-ext-strings-multi-mount`
**Date:** 2026-08-01

## User journeys

1. **As a user, before mounting anything, I want the detected drives shown as the primary
   list with a Refresh button — not labeled "Other available" — so the UI doesn't imply a
   primary drive exists when none does.**
2. **As a user with one drive mounted, I want the remaining unmounted drives listed below the
   mounted list under an "Other available devices" header with a small Refresh, above the
   security indicators, so I can mount a second drive without losing the mounted view.**

## Task report

### Task: Extract `OtherAvailableCopy` + `OtherAvailableSection` (copy + gating)
- **Summary:** Added two pure, testable symbols: `OtherAvailableCopy.label = "Other available
  devices"` and `OtherAvailableSection.label(isMounted:availableCount:) -> String?` (nil when
  idle or when mounted with nothing else available; the label only when mounted + ≥1 unmounted).
- **Validation:** `swift build --package-path gui --build-tests`
- **RED evidence:** compile-time — `error: cannot find 'OtherAvailableCopy' in scope` /
  `cannot find 'OtherAvailableSection' in scope` in `OtherAvailableCopyTests.swift` (commit
  `d45568e`). Failure caused by the missing symbols, not unrelated setup.
- **GREEN evidence:** `swift test --package-path gui` → `Test run with 154 tests in 2 suites
  passed` (commit `31115c6`).

### Task: Rework `PopoverContentView.mainContent` section (idle branch vs mounted branch)
- **Summary:** Replaced the single "Other available drives" block (gated only on
  `!otherAvailableDrives.isEmpty`, shown in both idle and mounted) with two branches:
  - **Idle** (`mountedDrives.isEmpty && !drives.isEmpty`): detected drives render as the
    primary list of mountable `DriveRow`s, with a Refresh pill (`RefreshGlyph` + `Text("Refresh")`,
    `.glassNeutral`) above the list. No section header.
  - **Mounted** (`OtherAvailableSection.label(...)` non-nil): remaining unmounted drives render
    below the mounted list under the "Other available devices" header + small icon-only Refresh
    (`.glassIcon`), above `SecurityIndicatorsView`. Position unchanged relative to security.
- **Validation:** `swift test --package-path gui`
- **GREEN evidence:** `Test run with 154 tests in 2 suites passed`.

### Task: Render guards
- **Summary:** Threaded `driveScanner` through the `renderPopover` test helper (default
  `DriveScanner()`, so existing call sites unchanged) and added two render tests via a
  `SeededListRunner` fake (same shape as `DriveScannerTests.FakeListRunner`):
  `idleWithDrivesRendersWithoutCollapsing` and `mountedWithUnmountedAvailableRendersSection`.
- **Validation:** `swift test --package-path gui`
- **GREEN evidence:** both tests passed (visible in run output).

### Task: Refactor
- **Summary:** Extracted `mountDrive(_:)` helper; the idle and mounted branches share one
  per-row Mount closure instead of two identical `Task { … }` blocks.
- **Validation:** `swift test --package-path gui` → 154 pass (commit `153fe0e`).

## Test specification

| # | What is guaranteed | Test | Type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | Section copy says "devices", not "drives" | `OtherAvailableCopyTests.labelSaysDevicesNotDrives` | unit | PASS | `swift test --package-path gui` |
| 2 | No section label when idle, even with drives available | `OtherAvailableCopyTests.noLabelWhenIdleEvenWithAvailableDrives` | unit | PASS | as above |
| 3 | No section label when mounted but nothing else available | `OtherAvailableCopyTests.noLabelWhenMountedButNothingElseAvailable` | unit | PASS | as above |
| 4 | Section label present when mounted + others available | `OtherAvailableCopyTests.labelWhenMountedAndOthersAvailable` | unit | PASS | as above |
| 5 | Idle-with-drives popover renders a non-empty image | `PopoverStateRenderTests.idleWithDrivesRendersWithoutCollapsing` | render | PASS | as above |
| 6 | Mounted + unmounted-available popover renders a non-empty image | `PopoverStateRenderTests.mountedWithUnmountedAvailableRendersSection` | render | PASS | as above |
| 7 | Existing mounted/mounted-multi/dirty/error/FDA states still render | `PopoverStateRenderTests.*` (unchanged) | render | PASS | 154 tests pass |

## Coverage and known gaps

- `swift test --package-path gui --enable-code-coverage` ran green (154 tests). The repo has no
  configured Swift coverage-threshold tooling (no xcov/llvm-cov step in the build), so a numeric
  percentage is not reported here — the gating logic is covered directly by the pure-symbol unit
  tests (1–4), and the view composition is covered structurally by the render guards (5–6).
- **Known gap (untestable here):** the ImageRenderer render tests assert non-collapse (image
  non-empty), not the literal presence/absence of the "Other available devices" string or the
  Refresh pill. The string content is covered indirectly via `OtherAvailableCopyTests`; the
  visual placement (Refresh pill above the list, section above security) is not asserted beyond
  non-collapse. This matches the existing `PopoverStateRenderTests` ceiling noted in its header.

## Merge evidence

Three checkpoint commits on `feat/ntfs-ext-strings-multi-mount`, in order:
- `d45568e` — `test: add reproducer … (RED)` — RED validated (compile-time, missing symbols).
- `31115c6` — `fix: split 'Other available' section … (GREEN)` — GREEN validated (154 pass).
- `153fe0e` — `refactor: extract mountDrive helper …` — refactor, tests stay green.

If squashed, carry this RED/GREEN/refactor summary into the squash body or PR description.