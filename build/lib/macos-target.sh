#!/bin/bash
# The shipping floor is independent of the SDK/OS used by the build machine.
# This checks load commands, not runtime compatibility on an older OS.
macos_target_activate() {
  export MACOSX_DEPLOYMENT_TARGET=14.0
}

macos_target_check_metadata() {
  /usr/bin/awk '
    $1 == "platform" { platforms++; if ($2 != "MACOS" && $2 != "1") bad=1 }
    $1 == "minos" {
      count++
      if ($2 !~ /^[0-9]+\.[0-9]+(\.[0-9]+)?$/) { bad=1; next }
      split($2, v, ".")
      if (v[1] < 10 || v[1] > 14 || (v[1] == 14 && (v[2] > 0 || v[3] > 0))) bad=1
    }
    END { exit (bad || count != 1 || platforms != 1) }
  '
}

macos_target_verify_binary() {
  local metadata
  metadata="$(/usr/bin/xcrun vtool -arch arm64 -show-build "$1" 2>&1)" || {
    echo "macos-target: FAIL — cannot inspect arm64 load commands: $1" >&2
    return 1
  }
  if ! printf '%s\n' "$metadata" | macos_target_check_metadata; then
    echo "macos-target: FAIL — missing/invalid macOS metadata or minimum exceeds 14.0: $1" >&2
    printf '%s\n' "$metadata" >&2
    return 1
  fi
  echo "macos-target: OK — arm64 minimum <= 14.0: $1"
}

macos_target_verify_runtime() {
  local bin failed=0
  for bin in anylinuxfs init-rootfs gvproxy vmnet-helper; do
    macos_target_verify_binary "$1/$bin" || failed=1
  done
  return "$failed"
}
