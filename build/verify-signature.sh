#!/bin/bash
# Verify every shipped macOS runtime signature.
#
# Asserts every signable shipped binary matches the selected local/ad-hoc or production identity,
# and carries no com.apple.quarantine xattr. anylinuxfs additionally must carry the
# com.apple.security.hypervisor entitlement (needed for real VM boot — see sign.sh).
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
BIN_DIR="${NTFSMAC_VENDOR_BIN_DIR:-$REPO_ROOT/vendor/bin}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

SIGNABLE=(anylinuxfs gvproxy init-rootfs vmnet-helper)

verify_one() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "verify-signature: FAIL — $path missing" >&2
    return 1
  fi
  if ! codesign -v "$path" >/dev/null 2>&1; then
    echo "verify-signature: FAIL — $path is not validly signed" >&2
    return 1
  fi
  local info
  info="$(codesign -dvvv "$path" 2>&1)"
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    if [[ "$info" != *"Signature=adhoc"* ]]; then
      echo "verify-signature: FAIL — $path is not ad-hoc signed" >&2
      return 1
    fi
  else
    if [[ "$info" != *"Authority=$SIGNING_IDENTITY"* || "$info" != *"TeamIdentifier=SQY8T23X8N"* ]]; then
      echo "verify-signature: FAIL — $path does not carry the BinaryBears Developer ID identity" >&2
      return 1
    fi
    if [[ "$info" != *"runtime"* ]]; then
      echo "verify-signature: FAIL — $path is missing Hardened Runtime" >&2
      return 1
    fi
  fi
  if xattr -p com.apple.quarantine "$path" >/dev/null 2>&1; then
    echo "verify-signature: FAIL — $path carries com.apple.quarantine" >&2
    return 1
  fi
  echo "verify-signature: OK — $path ($SIGNING_IDENTITY, no quarantine)"
  return 0
}

verify_hypervisor_entitlement() {
  local path="$1" entitlements
  entitlements="$(codesign -d --entitlements - --xml "$path" 2>/dev/null)"
  if [[ "$entitlements" != *"com.apple.security.hypervisor"* ]]; then
    echo "verify-signature: FAIL — $path is missing the com.apple.security.hypervisor entitlement" >&2
    return 1
  fi
  echo "verify-signature: OK — $path carries the hypervisor entitlement"
  return 0
}

verify_virtualization_entitlement() {
  local path="$1" entitlements
  entitlements="$(codesign -d --entitlements - --xml "$path" 2>/dev/null)"
  if [[ "$entitlements" != *"com.apple.security.virtualization"* ]]; then
    echo "verify-signature: FAIL — $path is missing the virtualization entitlement" >&2
    return 1
  fi
  echo "verify-signature: OK — $path carries the virtualization entitlement"
}

main() {
  local bin failed=0
  for bin in "${SIGNABLE[@]}"; do
    verify_one "$BIN_DIR/$bin" || failed=1
  done
  verify_hypervisor_entitlement "$BIN_DIR/anylinuxfs" || failed=1
  verify_hypervisor_entitlement "$BIN_DIR/init-rootfs" || failed=1
  verify_virtualization_entitlement "$BIN_DIR/vmnet-helper" || failed=1
  [[ $failed -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
