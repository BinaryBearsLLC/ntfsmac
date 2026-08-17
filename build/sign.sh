#!/bin/bash
# Sign every shipped macOS runtime binary.
#
# Signs every shipped macOS runtime binary. Local builds default to ad-hoc (`-s -`); the official
# release path supplies the BinaryBears Developer ID identity, Hardened Runtime, and timestamp.
# vmproxy is a Linux ELF guest binary and is never passed to codesign.
#
# anylinuxfs additionally gets build/entitlements/anylinuxfs.entitlements embedded:
# com.apple.security.hypervisor (needed to actually boot the libkrun microVM) and
# com.apple.security.cs.disable-library-validation (libkrun.dylib is dlopen'd and isn't
# signed with our identity). Confirmed real and necessary by inspecting upstream's own
# vendor/src/anylinuxfs/anylinuxfs.entitlements — though that file has a real typo,
# "com.apple.security.cs.disable-library-validationr" (trailing "r"), which silently
# no-ops the key. Our copy fixes the spelling; not a byte-for-byte vendor of theirs.
# gvproxy needs neither entitlement — plain ad-hoc, no plist.
#
# init-rootfs gets the same entitlements as anylinuxfs: it calls Hypervisor.framework
# directly via vmrunner-sys/vmrunner.go (cgo) to boot the VM itself on first rootfs
# init — same real requirement as anylinuxfs, confirmed by reading vmrunner.go's
# `#cgo darwin LDFLAGS: -framework Hypervisor`. Upstream's own build-app.sh signs it
# with the identical entitlements plist for this reason.
#
# The entitlement choices are documented in build/AUDIT.md and verified below.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
BIN_DIR="${NTFSMAC_VENDOR_BIN_DIR:-$REPO_ROOT/vendor/bin}"
ENTITLEMENTS="${NTFSMAC_ANYLINUXFS_ENTITLEMENTS:-$SCRIPT_DIR/entitlements/anylinuxfs.entitlements}"
VMNET_ENTITLEMENTS="${NTFSMAC_VMNET_HELPER_ENTITLEMENTS:-$SCRIPT_DIR/entitlements/vmnet-helper.entitlements}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"

SIGNABLE=(anylinuxfs gvproxy init-rootfs vmnet-helper)

main() {
  local bin path failed=0
  for bin in "${SIGNABLE[@]}"; do
    path="$BIN_DIR/$bin"
    if [[ ! -f "$path" ]]; then
      echo "sign.sh: $path missing, skipping" >&2
      continue
    fi

    local -a codesign_args=(-s "$SIGNING_IDENTITY" --force --timestamp=none "$path")
    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
      codesign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp "$path")
      if [[ -n "$SIGNING_KEYCHAIN" ]]; then
        codesign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --keychain "$SIGNING_KEYCHAIN" "$path")
      fi
    fi
    if [[ "$bin" == "anylinuxfs" || "$bin" == "init-rootfs" ]]; then
      if [[ ! -f "$ENTITLEMENTS" ]]; then
        echo "sign.sh: HARD-STOP — entitlements plist not found: $ENTITLEMENTS" >&2
        failed=1
        continue
      fi
      codesign_args=(-s "$SIGNING_IDENTITY" --force --timestamp=none --entitlements "$ENTITLEMENTS" "$path")
      if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        codesign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$path")
        if [[ -n "$SIGNING_KEYCHAIN" ]]; then
          codesign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --keychain "$SIGNING_KEYCHAIN" --entitlements "$ENTITLEMENTS" "$path")
        fi
      fi
    elif [[ "$bin" == "vmnet-helper" ]]; then
      if [[ ! -f "$VMNET_ENTITLEMENTS" ]]; then
        echo "sign.sh: HARD-STOP — vmnet-helper entitlements plist not found: $VMNET_ENTITLEMENTS" >&2
        failed=1
        continue
      fi
      codesign_args=(-s "$SIGNING_IDENTITY" --force --timestamp=none --entitlements "$VMNET_ENTITLEMENTS" "$path")
      if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        codesign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --entitlements "$VMNET_ENTITLEMENTS" "$path")
        if [[ -n "$SIGNING_KEYCHAIN" ]]; then
          codesign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --keychain "$SIGNING_KEYCHAIN" --entitlements "$VMNET_ENTITLEMENTS" "$path")
        fi
      fi
    fi

    if ! codesign "${codesign_args[@]}" 2>&1; then
      echo "sign.sh: HARD-STOP — failed to sign $path with $SIGNING_IDENTITY" >&2
      failed=1
      continue
    fi
    echo "sign.sh: signed $path with $SIGNING_IDENTITY"
  done
  [[ $failed -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
