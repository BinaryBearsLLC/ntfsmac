# BinaryBears branch and release workflow

This policy applies to [`BinaryBearsLLC/ntfsmac`](https://github.com/BinaryBearsLLC/ntfsmac).
The original project remains [`khr898/ntfsmac`](https://github.com/khr898/ntfsmac).

## Permanent branches

| Branch | Purpose |
| --- | --- |
| `main` | Exact, clean mirror of `upstream/main`; never receives BinaryBears branding or product work. |
| `dev` | BinaryBears integration and release source for v3 and later. |
| `archive/dev-pre-v3-rebrand` | Read-only recovery pointer to pre-rebrand commit `98dd96b`. |

The signed tag `dev-pre-v3-rebrand-20260817` points to the same archived commit. Do not delete or
move either recovery ref.

## BinaryBears changes

Create focused branches from current `dev` and target pull requests back to `dev`:

```sh
git switch dev
git pull --ff-only origin dev
git switch -c feat/<focused-topic>
```

Keep implementation, tests, and the smallest necessary documentation update together. `dev` may
also receive direct maintainer commits when preparing a coordinated release, but each commit must
remain reviewable and pass the relevant gate.

## Upstream mirror and contributions

Update `main` only by fast-forwarding from the real upstream:

```sh
git fetch --all --prune --tags
git switch main
git merge --ff-only upstream/main
git push origin main
```

Do not automatically merge `main` into `dev`. Upstream reconciliation is a separate, reviewed unit
that must preserve BinaryBears product behavior and is not a prerequisite for the v3 rebrand.

An upstream contribution starts independently from `upstream/main`, contains no BinaryBears-only
branding or roadmap material, and is submitted only after explicit maintainer approval.

## Release refs

For the 3.1.3 qualification cycle, `3.1.2` preserves `dev` at `b0ff6cd` and
`Update/3.1.3` contains the dependency and compatibility work. Both version pointers are local
until explicitly published. `dev` remains unchanged until the maintainer approves integration.
Do not remove either version pointer during cleanup. The old
`maintenance/dependency-refresh-2026-08` local branch was removed only after confirming that its
tip (`a7066b8`) is an ancestor of `Update/3.1.3`; its commits remain recoverable there.

GitHub is not yet a complete backup of the 3.1.3 worktree. Unpushed commits, uncommitted changes,
ignored build/runtime caches, installation backups, VM disks and private test logs are local.
Do not delete the local checkout or VM on the assumption that cloning GitHub will restore them.

- Official BinaryBears releases are built only from signed `vX.Y.Z` tags reachable from `dev`.
- The plist version must exactly equal the workflow input and tag without the `v` prefix.
- A workflow creates a draft Release. The downloaded draft artifact is tested before the same
  Release is published; rebuilding between those steps is forbidden.
- Never force-push `main`, `dev`, an archive ref, or a published release tag.

## Safe defaults

- Check the worktree, remotes, and ancestry before every synchronization or release.
- Use `git pull --ff-only`; stop and inspect divergence.
- Keep credentials, notarization inputs, local hardware evidence, and build output outside Git.
- Do not call a source-only fix released until the packaged artifact passes its stated gate.

All four upstream PRs prepared in August 2026 were merged by the upstream maintainer. The fork's
`main` currently follows that accepted upstream tree; the BinaryBears v3 line remains on `dev`.
