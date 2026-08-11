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

| Order | Local branch and tip | Relative contribution | Exact local evidence |
| --- | --- | --- | --- |
| 1 of 4 | `upstream-pr/1of4-runtime-alpine` (`ebb3aad`) | Immutable Alpine runtime, versioned cache migration, installed-version diagnostics, packaging gate | 91 targeted Bats; 208 Swift tests |
| 2 of 4 | `upstream-pr/2of4-mount-truth` (`b092fe2`) | Authoritative GUI/CLI mount reconciliation and fail-closed private NFS transport contract | 70 targeted Bats; 220 Swift tests |
| 3 of 4 | `upstream-pr/3of4-anylinuxfs-update-policy` (`9a43902`) | Read-only anylinuxfs update audit workflow and policy | 4 Bats; ShellCheck; real `v0.19.0` preflight with `repository_mutated=false` |
| 4 of 4 | `upstream-pr/4of4-live-security` (`6ef1d6b`) | Atomic runtime replacement, combined discovery probes, external-unmount recovery, and per-session PF/VPN transaction | 263 Bats; 222 Swift tests; tracked-script ShellCheck; full GUI source build; signed arm64 app and verified DMG |

The final DMG from the exact fourth tip has SHA-256
`43dcb1aac04c9dc0eec86b3e5afb404331d8d57ad0c73a201e9c76757e2f4f03`. The documented
packaged NTFS/VPN-on hardware evidence remains valid; the explicitly open VPN-off, concurrent-drive,
restart/crash, and physical hot-unplug cells remain release gates.

This is a dependency series, so do not open all four pull requests against upstream `main` at once:

1. publish and open `1of4` against the then-current `khr898/ntfsmac:main`;
2. after it merges, fetch the maintainer's result and rebuild only the `2of4` relative delta from
   the new `upstream/main`;
3. repeat for `3of4` and `4of4`, rerunning the candidate-specific and final gates each time;
4. never force-push a reviewed branch or assume the maintainer's merged tree equals the submitted
   commit; the accepted upstream implementation becomes authoritative.

The candidate branches and pull requests are still local/prepared only. Publishing them or
deleting corresponding remote fork branches is a separate maintainer action.

After the safe local cleanup, the only local heads retained are `dev`, `main`, and the four
ordered `upstream-pr/*` candidates above. Local `main` tracks `upstream/main` directly. The fork
remote still contains `dev`, `main`, `fix/p0-mount-truth-network-contract`, and
`fix/p0-pin-runtime-alpine-settings-hide`; the two obsolete remote topic heads were deliberately
left untouched, and the reconciliation documentation commit on `dev` was not pushed.

For product priorities, see [`BINARYBEARS_ROADMAP.md`](BINARYBEARS_ROADMAP.md). For build and GUI
contracts, see [`dev/PLAN.md`](dev/PLAN.md) and [`dev/GUI-PLAN.md`](dev/GUI-PLAN.md).
