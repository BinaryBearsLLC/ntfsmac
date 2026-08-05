# BinaryBears Upstream Regression Audit — 2026-08-05

> [!IMPORTANT]
> This audit applies only to the BinaryBears fork. It documents recovery branches for
> `BinaryBearsLLC/ntfsmac:dev`; it does not request or apply changes to `khr898/ntfsmac`.

## Scope and baselines

The review compared the following history and trees:

- current upstream and BinaryBears `main`: `d2b151d` (`v2.0.050826`);
- current BinaryBears `dev`: `4bffb0b`, whose product source matches `d2b151d` while preserving
  the pre-v2 fork history and BinaryBears-only documentation;
- preserved pre-sync BinaryBears feature tip: `e9f85e5`;
- upstream's PR-stack repair commit: `38e8b93`;
- the individual BinaryBears feature commits and their later upstream implementations.

The audit used commit archaeology, path-level tree comparison, call-site tracing, and focused
tests. A feature was classified as retained only when its current production path remained wired,
not merely because a type, helper, or test still existed somewhere in the tree.

## Root cause

Upstream accepted the BinaryBears PR series and then repaired conflicts created while combining
the stack. Commit `38e8b93` records that the conflicts had been resolved with **accept incoming**,
which left a half-refactored tree before the repair. That repair restored buildability and many
definitions, but four user-facing connections or pieces of presentation remained absent in the
final v2 tree.

This explains why both BinaryBears `main` and `dev` compiled successfully while presenting fewer
features: `dev` intentionally took upstream's final v2 product tree as authoritative. The older
BinaryBears commits were preserved in history, not replayed over the newer upstream code.

## Findings

### Confirmed regressions

| Area | Current v2 evidence | User-visible result | Recovery branch |
| --- | --- | --- | --- |
| Diagnose controls | The phase model, Hide support, JSON exporter, and modifier resolver remained, but the main popover did not pass `onHide` and neither Diagnose button used the Command-click action resolver. | Hide was absent from the normal popover and Command-click could not open the JSON save flow. | `codex/restore-diagnose-controls` (`74844cf`) |
| Complete GUI diagnostics | CLI JSON still produced the full privacy-safe schema and Swift decoded it, but the GUI summary exposed only four legacy rows. | The normal Diagnose view concealed version, kernel pin, helper state, VPN presence, and NFS mount count. | `codex/restore-complete-diagnostics` (`75371bc`) |
| Settings metadata | Dynamic `ProductVersion` resolution and tests remained, but `PreferencesView` no longer rendered `settingsText`. | Version/build disappeared from Settings. The inline uninstall confirmation also lost its card styling and its accessibility label was applied to the whole page. | `codex/restore-settings-metadata` (`bf44cf6`) |
| Full Disk Access guidance | The helper's friendly bundle display name remained, but the final prompt omitted the explanation for the technical service name and generic executable icon. | Users could reasonably distrust or misidentify the standalone privileged helper in System Settings. | `codex/restore-helper-fda-guidance` (`cff91d8`) |

### Confirmed retained behavior

The following previously delivered work remains present in the current v2 product code and must
not be replaced with older whole-file snapshots:

- interactive release builder and packaging verification;
- single-instance guard;
- real Service Management state for Launch at login;
- adaptive template idle menu-bar icon and explicit colored activity states;
- contextual diagnostic status and control help;
- in-popover Settings with Back navigation;
- MBR `Windows_NTFS` discovery;
- friendly helper display name;
- privacy-safe CLI diagnostic JSON and bundle-derived version metadata;
- helper reinstall and in-popover confirmed uninstall;
- lazy XPC connection and helper recovery;
- later upstream multi-drive, ext-filesystem, Quit/helper-exit, and Settings-layout fixes.

### Not a regression

- **SECURITY Hide** is a planned roadmap item, not a feature that previously shipped. Diagnostic
  Hide is the feature recovered here.
- A custom icon for the installed privileged helper was not lost. The SMJobBless helper is a
  standalone `CFBundlePackageType=TOOL` binary without an application resource bundle, so macOS
  may show a generic executable icon in Full Disk Access. The recovery branch restores accurate
  guidance instead of claiming unsupported icon behavior.
- The complete diagnostic data was not removed from the CLI schema. The regression affected GUI
  presentation and the GUI entry point for the existing developer export.

## Recovery design

Each recovery is deliberately based on `dev` at `4bffb0b`, limited to one concern, and keeps the
newer upstream v2 architecture. No branch restores an old full file or reverts later upstream
fixes.

Recommended PR and merge order into BinaryBears `dev`:

1. `codex/restore-diagnose-controls` — `74844cf`
2. `codex/restore-complete-diagnostics` — `75371bc`
3. `codex/restore-settings-metadata` — `bf44cf6`
4. `codex/restore-helper-fda-guidance` — `cff91d8`
5. `codex/document-upstream-regression-audit` — this document

The four code branches change independent or narrowly separated areas and are intended to remain
individually reviewable. `main` should remain a clean mirror of upstream; fork-only recoveries
belong in `dev`.

## Validation evidence

| Branch | Automated validation |
| --- | --- |
| `codex/restore-diagnose-controls` | `swift test`: 204 tests passed |
| `codex/restore-complete-diagnostics` | `swift test`: 207 tests passed, including preservation of every CLI JSON field and privacy-key rejection |
| `codex/restore-settings-metadata` | `swift test`: 204 tests passed |
| `codex/restore-helper-fda-guidance` | `swift test`: 204 tests passed |

The four recovery commits were also applied in the recommended order to a detached integration
worktree: all applied without conflicts and the combined snapshot passed 207/207 Swift tests.
The real checkout, which contains the ignored built vendor artifacts that secondary worktrees do
not materialize, passed all 196 tests in `bash tests/run-all.sh`, including the 16 CLI Diagnose
tests and package/signature checks.

Automated tests validate compilation, state transitions, parsing, presentation decisions, and
privacy constraints. After the branches are merged into `dev`, a packaged-app manual pass must
still confirm popover layout, modifier-click behavior, save-panel behavior, uninstall lifecycle,
and clean-install helper guidance. USB/VPN mount qualification remains a separate hardware gate.
