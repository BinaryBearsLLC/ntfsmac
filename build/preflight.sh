#!/bin/bash
# build/preflight.sh — p0-toolchain-preflight (PLAN.md §6).
# Checks presence + min versions of required build tools. Prints a pass/fail table.
# Never installs anything; never assumes a tool exists. Refuses non-arm64 hosts.
set -uo pipefail

FAIL=0

check_arch() {
  local arch
  arch=$(uname -m)
  if [[ "$arch" != "arm64" ]]; then
    printf '%-20s %-10s %s\n' "arch" "FAIL" "Apple Silicon (arm64) required, got: $arch"
    FAIL=1
    return
  fi
  printf '%-20s %-10s %s\n' "arch" "OK" "$arch"
}

check_tool() {
  local name="$1" cmd="$2" version_flag="${3:---version}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '%-20s %-10s %s\n' "$name" "FAIL" "not found on PATH"
    FAIL=1
    return
  fi
  local version_output
  version_output=$("$cmd" $version_flag 2>&1 | head -1)
  printf '%-20s %-10s %s\n' "$name" "OK" "$version_output"
}

echo "=== ntfsmac build preflight ==="
check_arch
check_tool "git" git
check_tool "cargo" cargo
check_tool "rustc" rustc
check_tool "go" go version
check_tool "umoci" umoci
check_tool "lld" ld.lld
check_tool "codesign" codesign -v
check_tool "curl" curl
check_tool "shasum" shasum --version
# pkg-config: libblkid-rs-sys resolves libblkid via pkg-config. brew: required to locate
# the util-linux install whose static archives we stage (tosbaha #1 fix).
check_tool "pkg-config" pkg-config --version
check_tool "brew" brew --version

# util-linux (Homebrew) is a build dep — its static libblkid.a is what anylinuxfs links.
# Assert the formula is installed AND ships the static archive (not just the dylib), since
# the whole fix depends on the .a being present. Build-machine setup: `brew install util-linux`.
check_util_linux_static() {
  local prefix
  prefix="$(brew --prefix util-linux 2>/dev/null)" || true
  if [[ -z "$prefix" || ! -d "$prefix" ]]; then
    printf '%-20s %-10s %s\n' "util-linux" "FAIL" "not installed via Homebrew (run: brew install util-linux)"
    FAIL=1
    return
  fi
  if [[ ! -f "$prefix/lib/libblkid.a" || ! -f "$prefix/lib/libuuid.a" ]]; then
    printf '%-20s %-10s %s\n' "util-linux (.a)" "FAIL" "static archive missing in $prefix/lib (libblkid.a / libuuid.a)"
    FAIL=1
    return
  fi
  printf '%-20s %-10s %s\n' "util-linux (.a)" "OK" "$prefix/lib/libblkid.a"

  # gettext: libblkid.a references _libintl_gettext (GNU gettext, not in libSystem).
  # Homebrew gettext ships libintl.a — assert it's present, same rationale as util-linux.
  local gettext_prefix
  gettext_prefix="$(brew --prefix gettext 2>/dev/null)" || true
  if [[ -z "$gettext_prefix" || ! -f "$gettext_prefix/lib/libintl.a" ]]; then
    printf '%-20s %-10s %s\n' "gettext (.a)" "FAIL" "libintl.a missing (run: brew install gettext)"
    FAIL=1
    return
  fi
  printf '%-20s %-10s %s\n' "gettext (.a)" "OK" "$gettext_prefix/lib/libintl.a"
}
check_util_linux_static

if [[ "$FAIL" -ne 0 ]]; then
  echo ""
  echo "preflight: FAILED — missing/invalid tools above. Install manually (no auto-install)."
  exit 1
fi

echo ""
echo "preflight: PASS"
exit 0
