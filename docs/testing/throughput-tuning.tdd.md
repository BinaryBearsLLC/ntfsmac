# TDD Evidence: Default-on NFS throughput tuning (Tier 1)

**Source plan:** inline `/ecc:plan` + `/ecc:tdd-workflow` session, 2026-08-02. No `*.plan.md` file; journeys derived in-session. User decision: Tier 1 only (rsize/wsize/readahead), both CLI + GUI, no new GUI controls, default-on (PLAN.md L8 owner override).

**Scope:** increase NFS read/write transfer speed without touching device filtering or mounting logic. No `async` export (Tier 2) — explicitly excluded.

## User journeys

1. As a CLI user, I want larger NFS transfer units by default, so that bulk reads/writes are faster without me passing flags.
2. As a GUI user, I want the same speedup with no new preference to manage, so that mounting a drive is automatically faster.
3. As the project owner, I want the data-loss-class lever (`async` export) to stay absent, so that default behavior never risks unflushed writes on unclean disconnect.

## Task report

### Task 1 — RED: bats reproducer
- **Summary:** added two bats cases asserting `rsize=1048576`, `wsize=1048576`, `readahead=16` are always present in `--nfs-options` (default mount and `--read-only` mount).
- **Validation:** `bats tests/cli/mount.bats`
- **RED evidence:** `not ok 8 always appends rsize/wsize/readahead tuning (default mount)` — `[[ "$output" == *"rsize=1048576,wsize=1048576"* ]]' failed`; `not ok 9 tuning is present alongside --read-only` — `[[ "$output" == *"readahead=16"* ]]' failed`. Existing 22 tests stayed green.
- **Checkpoint:** `f1ca1c8 test: add reproducer for default-on NFS throughput tuning (RED)`.

### Task 2 — GREEN: wire tuning in nfs-mount.sh
- **Summary:** append `rsize=1048576,wsize=1048576,readahead=16` to `nfs_opts` in `cli/lib/nfs-mount.sh` after `soft`/`ro`. Always on; no env gate; no flag.
- **Validation:** `bats tests/cli/mount.bats`
- **GREEN evidence:** `ok 8`, `ok 9`; full file 24/24 ok. Sibling bats suites re-run for regression: `diagnose`, `fs-driver`, `install`, `list-drives`, `mount`, `pf-rules`, `route-guard`, `run-with-progress`, `signing`, `teardown`, `uninstall`, `unmount`, `validate-device` — 0 `not ok`.
- **Both surfaces:** GUI path is `helper → ntfsmac mount → cli/commands/mount.sh → cli/lib/nfs-mount.sh`; tuning lives in the shared leaf, so the GUI inherits it with **no XPC, Settings, PreferencesView, or helper-rebuild change** — satisfies "do not add new controls to GUI."
- **Checkpoint:** `c18fef3 feat: default-on NFS throughput tuning rsize/wsize/readahead (GREEN)`.

### Task 3 — Docs (PLAN.md only; README not updated per user)
- **Summary:** recorded the L8 owner override under `docs/dev/PLAN.md` L8, and revised R7 to note `async` stays absent while rsize/wsize/readahead carry no integrity surface.
- **Validation:** manual review.
- **Checkpoint:** included in this evidence report's commit.

## Test specification

| # | What is guaranteed | Test file or command | Test type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | Default mount emits `rsize=1048576`, `wsize=1048576`, `readahead=16` in `--nfs-options` | `tests/cli/mount.bats: always appends rsize/wsize/readahead tuning (default mount)` | unit (bats, stubbed anylinuxfs) | PASS | `bats tests/cli/mount.bats` → `ok 8` |
| 2 | `--read-only` mount keeps `soft,ro,` prefix and still includes all three tuning options | `tests/cli/mount.bats: tuning is present alongside --read-only` | unit (bats) | PASS | `bats tests/cli/mount.bats` → `ok 9` |
| 3 | `soft` stays first and `hard` never emitted (regression guard) | `tests/cli/mount.bats: mounts a valid device with soft NFS mode, hard never emitted` | unit (bats) | PASS | `ok 1` (pre-existing, still green) |
| 4 | `--read-only` still appends `ro` (regression guard) | `tests/cli/mount.bats: --read-only appends ro to --nfs-options` | unit (bats) | PASS | `ok 7` (pre-existing, still green) |
| 5 | No regression across the CLI bats suite | `bats tests/cli/*.bats` | unit (bats) | PASS | 0 `not ok` across 13 files |

## Design rationale (risk reduction)

- `rsize`/`wsize=1MB`: NFSv3-over-TCP max transfer unit. Kernel auto-negotiates down to the Linux nfsd cap; never fails, no data-integrity surface. `rsize == wsize` avoids the macOS `mount_nfs` high-ratio readahead warning ("unexpected readahead RPCs").
- `readahead=16`: macOS `mount_nfs` read-ahead window; pure prefetch, no integrity path. `readahead` confirmed a valid macOS `mount_nfs` option (`man mount_nfs`).
- `async` export (Tier 2) deliberately **not** included — that is the data-loss lever L8 protects against (acknowledges writes before stable storage; loss on unclean disconnect). Remains opt-in/absent.

## Coverage and known gaps

- Bats covers the option-string contract (what `nfs-mount.sh` passes to `anylinuxfs`). No coverage of the GUI Swift side because the GUI path needs **no code change** — it inherits tuning from the shared shell layer.
- **Not measured here:** real end-to-end throughput delta. Validating the actual MB/s gain requires real hardware (`dd` read/write, tuned-vs-untuned) and cannot run in this environment. Owner to run on real M3.
- **Not covered:** the `nfsstat -m` post-mount check that would prove the kernel accepted 1 MB (vs negotiated down). Optional follow-up: add to `diagnose`.

## Merge evidence

- RED: `f1ca1c8` — failing tests added and run (`not ok 8`, `not ok 9`).
- GREEN: `c18fef3` — minimal fix; same tests re-run (`ok 8`, `ok 9`), full file 24/24, sibling suites 0 failures.
- No refactor commit needed — change is 8 lines in one file plus a comment.