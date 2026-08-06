# Live Mount-State and NFS Transport Audit — 2026-08-06

## Scope

This audit records live behavior from the packaged ntfsmac 2.0 build 050826 on Apple Silicon
macOS 26.6 with one external MBR/NTFS test volume. It covers two trust questions discovered
while running the local SHA-256 transfer-integrity suite:

1. whether the GUI and CLI publish the same real mount state; and
2. whether the observed NFS endpoint matches the documented dedicated private `/30` contract.

The integrity suite itself passed. Generated data, three repeated Standard datasets, and a
2.23 GB real video retained matching sizes and SHA-256 values before and after a confirmed safe
unmount/remount. The findings below are therefore state-truth and architecture findings, not
evidence of payload corruption.

## Finding 1 — GUI mount state remains stale after CLI unmount

**Severity:** P0 release blocker. A green mounted/writable claim can outlive the mount it describes.

### Reproduction and observed evidence

1. The drive was mounted through the packaged GUI using the default `ntfs-3g` path.
2. `/usr/local/ntfsmac/bin/ntfsmac unmount <partition>` returned success and completed PF teardown.
3. Independent checks then agreed on the unmounted state:
   - the macOS mount table contained no matching NFS mount;
   - `diskutil info` reported `Mounted: No`;
   - `ntfsmac diagnose --json` reported `bridge: down` and `nfs_mount_count: 0`.
4. The still-running GUI instead showed:
   - `ntfsmac Mounted read/write`;
   - the stale drive row and an enabled `Unmount` button;
   - a green mounted presentation.
5. Clicking GUI Refresh did not change the mounted state.
6. Running GUI Diagnose produced `vmnet bridge: Inactive while a drive is mounted` and
   `NFS mounts: None` inside the same popover that still claimed `Mounted read/write`.

This is a direct cross-surface contradiction. The GUI is not currently suitable as an
authoritative mount or safe-removal indicator when CLI/external actions can occur.

### Code boundary

- `MountController.mountedDrives` is populated after a successful GUI helper mount response and
  removed only after a successful GUI helper unmount response.
- `DriveScanner` polls `anylinuxfs list`, which enumerates compatible physical partitions; it
  updates availability but never reconciles `MountController.mountedDrives`.
- The Refresh button invokes only `DriveScanner.refresh()`.
- Diagnose reads real CLI state, but its report is used only for diagnostic rows and does not
  reconcile the header, icon, mounted rows, or controls.

The defect is therefore systemic rather than a delayed refresh: no current data flow converts
observed external mount state into the GUI controller's mounted set.

### Required remediation

Create a read-only mount-state provider that produces a per-device snapshot from actual
ntfsmac-owned mounts/sessions. Reconcile the GUI cache against that snapshot at every lifecycle
boundary listed in the roadmap. Treat helper command success as provisional until the observed
mount state agrees. When sources disagree, publish a reason-coded warning or unknown state and
retain recovery controls without showing green.

Required tests include both directions (GUI action observed by CLI and CLI action observed by the
already-running GUI), manual/external unmount, helper or VM death, hot unplug, app restart after a
crash, refresh, delayed teardown, and concurrent mounts where only one disappears.

### Remediation implemented after the audit

The P0 branch now pairs `anylinuxfs status` with `/sbin/mount -t nfs` per device and mount point.
It reconciles at launch, popover open, every five seconds, Refresh, and after helper completion.
An authoritative empty snapshot removes stale rows; incomplete or contradictory evidence retains
recovery controls but changes the aggregate presentation to yellow/unknown with a reason code.
Parser and state-machine tests cover CLI-created mounts, external unmount, unavailable evidence,
provisional helper success, and independent concurrent mounts. The packaged-app hardware matrix
remains open and is not replaced by these unit tests.

## Finding 2 — live logs expose a loopback NFS endpoint

**Severity:** P0 architecture/security proof gap. No integrity failure was observed.

### Observed evidence

Two consecutive mount-session logs contained the same sequence:

```text
vmproxy ... mount /dev/vda <label> -b 127.0.0.1 -t ntfs ...
Checking NFS server on 127.0.0.1:2049...
mount -t nfs ... diskNsN.local:/mnt/<label> /Volumes/<label>
```

The live host mount was NFS v3 with the required `soft` policy and 1 MiB read/write sizes. During
the mount, diagnostics reported an active vmnet bridge and one NFS mount. On teardown, the mount,
bridge, and session listener disappeared normally.

### Source-trace resolution

The vendored anylinuxfs source has two distinct network-helper paths. The observed `vmproxy -b
127.0.0.1` and loopback port check belong to the gvproxy path. In the vmnet-helper path,
anylinuxfs allocates a private `/30`, registers the VM endpoint behind the synthetic
`diskNsN.local` name, and the macOS NFS client routes directly through the private bridge.

The old diagnostic's `bridge=up` result did not disprove the loopback finding: its process check
treated gvproxy or anylinuxfs itself as bridge evidence. That false-positive heuristic has been
removed. ntfsmac now explicitly passes `--net-helper vmnet`, so a stale user-level anylinuxfs
setting cannot silently select gvproxy for an ntfsmac mount.

### Required investigation

- Resolve the synthetic `diskNsN.local` name during a live session and record the endpoint class.
- Inventory TCP/UDP port 2049 listeners, their owning processes, bind scopes, and lifecycle.
- Record the private vmnet host/guest addresses and routes locally, then correlate them with a
  packet trace for mount, I/O, and teardown. Raw addresses stay in local evidence, not exported
  privacy-safe diagnostics.
- Repeat with VPN off/on and two concurrent mounts to verify isolation, unique session routing,
  and teardown ownership.
- Confirm no listener is reachable through Wi-Fi, Ethernet, VPN, or another unrelated interface.
- Run `tests/live/verify-nfs-transport.sh` against the packaged candidate. It fails closed unless
  the observed ntfsmac mounts are `soft`, resolve inside the vmnet pool, route through a bridge,
  use vmnet-helper, and have no active gvproxy or loopback NFS listener.

### Remediation implemented after the audit

The selected product topology is direct private-link NFS. The mount wrapper now forces vmnet,
diagnostic schema 5 publishes only fixed `network_helper` and `nfs_transport_contract` tokens,
and active mounts degrade health unless the expected vmnet contract is observed. A read-only,
privacy-safe live gate enforces the listener/route/`soft` invariants. Its parser/contract tests
pass; VPN, concurrent-mount, teardown, helper-recovery, and packaged real-hardware executions
remain open release evidence.

## Release gates

The GUI/CLI issue passes only when every surface converges on the same per-device state after all
supported state transitions and never displays green during disagreement. The transport issue
passes only when listener, route, and packet evidence demonstrates the chosen documented topology
and clean teardown. Unit tests alone are insufficient for either gate; the packaged app and real
hardware are required.
