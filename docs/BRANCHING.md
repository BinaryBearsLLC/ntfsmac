# BinaryBears Branch and Upstream Workflow

> [!IMPORTANT]
> This workflow applies to the [`BinaryBearsLLC/ntfsmac`](https://github.com/BinaryBearsLLC/ntfsmac)
> fork. It does not change the contribution policy of
> [`khr898/ntfsmac`](https://github.com/khr898/ntfsmac).

The fork has two permanent branches with deliberately different responsibilities. Keeping those
roles separate prevents an upstream synchronization from mixing older fork implementations with
the maintainer's accepted and subsequently modified versions.

## Remotes

| Remote | Repository | Purpose |
| --- | --- | --- |
| `origin` | `BinaryBearsLLC/ntfsmac` | BinaryBears branches, CI, and pull requests |
| `upstream` | `khr898/ntfsmac` | Original project's current source of truth |

Verify these before any synchronization:

```sh
git remote -v
git fetch --all --prune --tags
```

## Permanent branches

| Branch | Contains | Must not contain |
| --- | --- | --- |
| `main` | The exact current upstream `main` tree | BinaryBears-only branding, roadmap work, or experimental features |
| `dev` | Current `main` plus the BinaryBears roadmap and integrated fork work | Unreviewed experiments or old copies of changes already finalized upstream |

`main` is the clean comparison and contribution base. `dev` is the branch used to build and test
the BinaryBears edition.

## Start BinaryBears work

One improvement gets one branch and one pull request:

```sh
git switch dev
git pull --ff-only origin dev
git switch -c feat/<focused-topic>
```

After implementation and validation, push that branch and open a PR targeting
`BinaryBearsLLC/ntfsmac:dev`. Do not target the fork's `main` with BinaryBears-only work. The fork
CI workflow runs for pushes and pull requests targeting both permanent branches; require its
successful jobs before merging into `dev`.

## Synchronize a new upstream release

First update the clean mirror:

```sh
git fetch --all --prune --tags
git switch main
git merge --ff-only upstream/main
git push origin main
```

Then integrate that exact result into BinaryBears development:

```sh
git switch dev
git merge --no-ff main
```

During conflict resolution:

1. prefer upstream for shared application, helper, CLI, build, and test code;
2. retain the BinaryBears roadmap, branch policy, fork README, and fork-only work that is not
   upstream;
3. do not replay an older fork implementation after upstream has accepted and modified it;
4. update documentation paths or status when upstream reorganizes files;
5. run the full relevant test and packaging gates before pushing `dev`.

This merge advances the common ancestry, so the next upstream synchronization is based on the
last resolved upstream version rather than the fork's original base.

## Prepare a possible upstream contribution

An upstream candidate is intentionally independent from `dev`:

```sh
git fetch upstream
git switch -c feat/<upstream-topic> upstream/main
```

The branch must contain only the focused change, its tests, and upstream-appropriate
documentation. It must exclude BinaryBears branding, roadmap, screenshots, and unrelated fork
commits. Push the branch to `origin` for CI and review. Opening a PR against `khr898/ntfsmac` is a
separate maintainer action and is never implied by pushing the branch.

## Safe defaults

- Use `git pull --ff-only` on `main` and ordinary topic branches. A divergent pull should stop and
  be inspected rather than automatically creating a merge commit.
- Merge `main` into the long-lived `dev`; do not merge `dev` into `main`.
- Do not rebase or force-push shared permanent branches as a routine synchronization method.
- Do not delete a recovery tag or archived branch until the replacement has passed CI and local
  validation.
- Check `git status --short --branch` before switching, merging, building, or publishing.

## Reconciliation record — 2026-08-05

- `origin/main` and `upstream/main` were verified at `d2b151d` (`v2.0.050826`).
- The previous BinaryBears `dev` tip was `e9f85e5`; it contained the roadmap but predated the
  maintainer's final accepted-PR integration and follow-up fixes.
- The replacement `dev` was rebuilt from `d2b151d`, then the BinaryBears documentation and
  roadmap were reapplied deliberately.
- The previous `dev` history remains an ancestor of the reconciled branch, so no force-push or
  history loss is required.

## Reconciliation and upstream candidate record — 2026-08-11

After `git fetch --all --prune --tags`, the repository was audited across every local and remote
branch plus both repositories' pull-request lists.

- `main`, `origin/main`, and `upstream/main` all resolve to `0725c31`
  (`v2.1.090826`) with identical trees.
- Every previous fork topic tip is already an ancestor of `dev`: runtime Alpine
  (`2fbb382`), mount/NFS truth (`e4a2ea7`), anylinuxfs update policy (`1bede82`), and live
  security completion (`762cc91`). No integration merge was missing.
- The former GUI restoration candidate `456a914` is already contained in `upstream/main` through
  upstream pull request 16 and is no longer an active proposal.
- No open pull request was found in either `khr898/ntfsmac` or `BinaryBearsLLC/ntfsmac` at audit
  time.

The upstream work was rebuilt as an ordered local series, independent from `dev` and rooted at the
current `upstream/main`. Each relative delta contains only shared implementation, tests, and
upstream-appropriate documentation; added lines contain no BinaryBears branding, roadmap links,
fork screenshots, or `origin/dev` references.

| Order | Branch and current tip | Relative contribution | Exact evidence |
| --- | --- | --- | --- |
| 1 of 4 | `upstream-pr/1of4-runtime-alpine` (`ebb3aad`) | Immutable Alpine runtime, versioned cache migration, installed-version diagnostics, packaging gate | 91 targeted Bats; 208 Swift tests |
| 2 of 4 | `upstream-pr/2of4-mount-truth` (`fdc45a9`) | Authoritative GUI/CLI mount reconciliation and fail-closed private NFS transport contract | 70 targeted Bats on the unchanged production delta; 220 Swift tests; deterministic responsiveness test passed 20 consecutive runs |
| 3 of 4 | `upstream-pr/3of4-anylinuxfs-update-policy` (`0f354ac`) | Read-only anylinuxfs update audit workflow and policy | 4 Bats; 220 Swift tests; ShellCheck; real `v0.19.0` preflight with `repository_mutated=false` |
| 4 of 4 | `upstream-pr/4of4-live-security` (`2f7e509`) | Atomic runtime replacement, combined discovery probes, external-unmount recovery, and per-session PF/VPN transaction | 263 Bats; 222 Swift tests; tracked-script ShellCheck; full GUI source build; signed arm64 app and verified DMG |

The final DMG from the exact fourth tip has SHA-256
`d9b7b53ef03dc8965233e0ccbb242fbc0d90ee8004c1e0459697db059c898e6a`. The documented
packaged NTFS/VPN-on hardware evidence remains valid; the explicitly open VPN-off, concurrent-drive,
restart/crash, and physical hot-unplug cells remain release gates.

## Upstream pull-request publication — 2026-08-12

All four candidate branches are published to `BinaryBearsLLC/ntfsmac`. The pull requests target
`khr898/ntfsmac:main`; only the first is ready for merge, while its dependants remain drafts:

| Order | Pull request | Review state | Merge rule |
| --- | --- | --- | --- |
| 1 of 4 | [`#17`](https://github.com/khr898/ntfsmac/pull/17) | Ready; all GitHub CI jobs passed on `ebb3aad` | Merge first |
| 2 of 4 | [`#18`](https://github.com/khr898/ntfsmac/pull/18) | Draft; all GitHub CI jobs passed on `fdc45a9`; cumulative on `1of4` | Refresh from the maintainer-accepted result of `#17`, rerun gates, then mark ready |
| 3 of 4 | [`#19`](https://github.com/khr898/ntfsmac/pull/19) | Draft; all GitHub CI jobs passed on `0f354ac`; cumulative on `2of4` | Refresh only after `#18` is accepted, then rerun gates |
| 4 of 4 | [`#20`](https://github.com/khr898/ntfsmac/pull/20) | Draft; all GitHub CI jobs passed on `2f7e509`; cumulative on `3of4` | Refresh only after `#19` is accepted, then rerun all final gates |

The first `#18` CI run exposed a wall-clock-sensitive Swift test: the main actor remained responsive,
but a loaded runner exceeded the test's fixed 350 ms threshold. Commit `fdc45a9` replaced that timing
assertion with a deterministic child-process handshake. It changes test code only, passed 20
consecutive focused runs (including runs slower than the former threshold), and passed the complete
220-test Swift suite. `3of4` and `4of4` were then rebuilt on that exact predecessor. `git range-diff`
confirmed their one-commit and five-commit relative contributions are patch-equivalent to the
previously validated versions; the only inherited tree change is the deterministic test.

For each dependency transition:

1. fetch the maintainer's merged `upstream/main` rather than assuming it equals the submitted tip;
2. rebuild only the next PR's relative delta on that accepted tree;
3. rerun its candidate-specific gates and update the recorded tip and evidence;
4. keep later PRs draft and never merge the cumulative branches out of order.

After the safe local cleanup, the only local heads retained are `dev`, `main`, and the four
ordered `upstream-pr/*` candidates above. Local `main` tracks `upstream/main` directly. The fork
remote contains `dev`, `main`, and the same four ordered candidate branches. The obsolete remote
P0 topic heads have been removed because both fixes are already contained in the ordered series.

For product priorities, see [`BINARYBEARS_ROADMAP.md`](BINARYBEARS_ROADMAP.md). For build and GUI
contracts, see [`dev/PLAN.md`](dev/PLAN.md) and [`dev/GUI-PLAN.md`](dev/GUI-PLAN.md).
