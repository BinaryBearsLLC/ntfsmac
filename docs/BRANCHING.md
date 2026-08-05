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

For product priorities, see [`BINARYBEARS_ROADMAP.md`](BINARYBEARS_ROADMAP.md). For build and GUI
contracts, see [`dev/PLAN.md`](dev/PLAN.md) and [`dev/GUI-PLAN.md`](dev/GUI-PLAN.md).
