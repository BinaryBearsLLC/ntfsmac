# Live P0 Security Transaction Audit — 2026-08-11

## Scope

This audit records the privacy-safe evidence retained from the packaged ntfsmac 2.1 (090826)
candidate on Apple Silicon macOS 26.6.1. One real NTFS USB device was exercised while a VPN owned
the default route. It validates one important VPN-on cell; it does not replace the remaining
VPN-off, concurrent-device, crash/restart, or physical hot-unplug release matrix.

No persistent user, device, volume, address, interface, VPN-provider, or PF-token identifier is
recorded here. The generated transfer pair was removed after verification; pre-existing USB data
was not modified.

## Finding and remediation: pre-NFS VPN ordering

The first packaged mount started the vmnet backend but timed out waiting for NFS. Live routing
still sent the new guest endpoint through the pre-existing VPN. The former transaction discovered
and secured the private link only after the complete anylinuxfs mount command returned, but that
command itself waits for NFS readiness. This created a circular ordering failure.

The remediated wrapper now:

1. snapshots existing validated private vmnet `/30` bridges;
2. starts the bounded anylinuxfs mount under supervision;
3. observes only the newly created validated bridge, endpoint, and subnet;
4. installs and reads back the direct-child PF policy and repairs an exact VPN-captured endpoint
   route before the backend NFS readiness check can complete;
5. carries the PF token and optional route ownership into the final real-mount/status proof; and
6. releases early resources on backend/final-proof failure, preserving cleanup-pending state only
   when release itself cannot be proven.

Automated tests cover pre-NFS ordering, malformed/ambiguous discovery, backend failure, early
resource release, final soft-NFS verification, concurrent ownership, stale-session recovery,
unparseable PF enable-token output, unsafe state entries, and replacement of an owned host route
by another interface before teardown. Unknown ownership is preserved as cleanup-pending, and a
replacement route is measured but never deleted.

## Retained live evidence

- The packaged GUI completed a read/write mount with the active VPN default route.
- Diagnostic schema 5 reported the expected vmnet transport, a private `/30` endpoint/route, one
  NFS mount, and verified `soft` semantics.
- `tests/live/verify-nfs-transport.sh` returned:

  ```text
  verify-nfs-transport: PASS — 1 ntfsmac mount(s), vmnet/private/soft, no loopback listener
  ```

- Effect checks reached the intended NFS and mountd ports through the private endpoint while
  unrelated tested bridge ports were blocked or closed.
- A generated 32 MiB payload matched by size, byte comparison, and SHA-256 after writing and
  rereading through the mounted volume:

  ```text
  29efb03c7cc5be106c13f321e212b997e445e37430ff4329fdcb1f9099434bc8
  ```

- App Unmount removed the host NFS mount, anylinuxfs session, private VM/bridge, and owned route.
- Finder Disconnect on the synthetic NFS share removed the client mount; the open app detected
  it and completed backend/PF/route cleanup without retaining a green mounted state.
- A later external NFS unmount repeated the same reconciliation result. The endpoint route returned
  to the pre-existing VPN after teardown.
- The maintainer reported running the root-only security-transaction gate. Its stdout was not
  captured in the agent transcript, so this audit does not promote that report to retained proof.

## Adjacent live fixes validated in the same candidate

- Runtime/helper installation now uses a fresh same-directory inode and atomic rename before
  signature verification, avoiding stale-vnode signature failures after replacing a running
  ad-hoc-signed executable. No signing, entitlement, Gatekeeper, SIP, quarantine, or TCC policy is
  weakened.
- Drive discovery combines the anylinuxfs Microsoft and Linux probes and deduplicates their rows.
  This prevents a valid NTFS device from disappearing when the backend's bare list returns no row.
- Mount polling cannot overwrite an in-flight helper operation with an idle GUI snapshot.

## Unmount surface semantics

App Unmount is the canonical owner-driven transaction and is preferred. Finder Disconnect acts
only on the synthetic NFS client mount; the app's reconciliation path must finish VM/PF/route
cleanup, which passed here. Finder eject of the physical USB device is a distinct whole-device
Disk Arbitration operation and was not tested. The safe operator order is: App Unmount, wait for
the detected/unmounted GUI state, then eject the physical device.

## Open release evidence

- Repeat the live transport and root security gates with the VPN default route absent.
- Repeat with two concurrent devices and prove isolated teardown of only one session.
- Exercise CLI-created mount discovery, helper reconnect, app restart, and crash recovery.
- Exercise physical whole-device eject and hot-unplug only after a controlled data-safety plan.
- Retain the exact privacy-safe root-gate PASS output in the release PR evidence.
