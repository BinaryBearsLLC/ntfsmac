#!/bin/bash
# build/build-gvproxy.sh — v-gvproxy (PLAN.md §6).
# Builds gvproxy from source (containers/gvisor-tap-vsock) at the sources.lock pin,
# NOT anylinuxfs's prebuilt gvproxy-darwin (that's a settled PLAN.md cut). Cross-checks
# the pinned tag against anylinuxfs's own download-dependencies.sh and warns on drift.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
# shellcheck source=lib/lock.sh
source "$SCRIPT_DIR/lib/lock.sh"
# shellcheck source=lib/go-toolchain.sh
source "$SCRIPT_DIR/lib/go-toolchain.sh"

CACHE_DIR="${NTFSMAC_GVPROXY_CACHE_DIR:-$REPO_ROOT/build/.cache/gvisor-tap-vsock}"
BIN_DIR="${NTFSMAC_VENDOR_BIN_DIR:-$REPO_ROOT/vendor/bin}"
UPSTREAM_URL="https://github.com/containers/gvisor-tap-vsock.git"

# warn_on_tag_drift <lock_version> <anylinuxfs_script>
# Non-fatal: anylinuxfs's own download-dependencies.sh pins its own GVPROXY_VERSION.
# If it has drifted from our sources.lock pin, warn loudly but don't block the build —
# we deliberately build from source instead of using anylinuxfs's prebuilt binary anyway.
warn_on_tag_drift() {
  local lock_version="$1" anylinuxfs_script="$2" upstream_version
  [[ -f "$anylinuxfs_script" ]] || { echo "build-gvproxy: WARN — anylinuxfs's download-dependencies.sh not found at $anylinuxfs_script, skipping drift check" >&2; return 0; }
  upstream_version="$(grep -E '^GVPROXY_VERSION=' "$anylinuxfs_script" | head -1 | cut -d'"' -f2)"
  if [[ -z "$upstream_version" ]]; then
    echo "build-gvproxy: WARN — could not parse GVPROXY_VERSION from $anylinuxfs_script" >&2
    return 0
  fi
  local lock_version_bare="${lock_version#v}"
  if [[ "$upstream_version" != "$lock_version_bare" ]]; then
    echo "build-gvproxy: WARN — sources.lock pins gvproxy v${lock_version_bare}, anylinuxfs's download-dependencies.sh pins v${upstream_version}. Drift detected, not blocking (we build from source)." >&2
  else
    echo "build-gvproxy: tag matches anylinuxfs's own pin (v${upstream_version}) — no drift"
  fi
}

main() {
  local version commit x_crypto_version expected_overlay_sha256
  version="$(lock_get GVPROXY_VERSION)" || { echo "build-gvproxy: HARD-STOP — GVPROXY_VERSION missing from sources.lock" >&2; exit 1; }
  commit="$(lock_get GVPROXY_COMMIT)" || { echo "build-gvproxy: HARD-STOP — GVPROXY_COMMIT missing from sources.lock" >&2; exit 1; }
  x_crypto_version="$(lock_get GVPROXY_X_CRYPTO_VERSION)" || { echo "build-gvproxy: HARD-STOP — GVPROXY_X_CRYPTO_VERSION missing from sources.lock" >&2; exit 1; }
  expected_overlay_sha256="$(lock_get GVPROXY_GO_OVERLAY_SHA256)" || { echo "build-gvproxy: HARD-STOP — GVPROXY_GO_OVERLAY_SHA256 missing from sources.lock" >&2; exit 1; }
  if [[ "$version" == "TODO-UNRESOLVED" || "$commit" == "TODO-UNRESOLVED" ||
        "$x_crypto_version" == "TODO-UNRESOLVED" || "$expected_overlay_sha256" == "TODO-UNRESOLVED" ]]; then
    echo "build-gvproxy: HARD-STOP — one or more gvproxy pins are unresolved (TODO-UNRESOLVED)" >&2
    exit 1
  fi
  if [[ ! "$x_crypto_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ||
        ! "$expected_overlay_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "build-gvproxy: HARD-STOP — malformed x/crypto version or module-overlay hash pin" >&2
    exit 1
  fi

  warn_on_tag_drift "$version" "$REPO_ROOT/vendor/src/anylinuxfs/download-dependencies.sh"

  mkdir -p "$BIN_DIR" "$(dirname "$CACHE_DIR")"
  if [[ -d "$CACHE_DIR/.git" ]]; then
    git -C "$CACHE_DIR" fetch --quiet --tags origin
  else
    rm -rf "$CACHE_DIR"
    git clone --quiet "$UPSTREAM_URL" "$CACHE_DIR"
  fi
  git -C "$CACHE_DIR" checkout --quiet "$commit"

  local head
  head="$(git -C "$CACHE_DIR" rev-parse HEAD)"
  if [[ "$head" != "$commit" ]]; then
    echo "build-gvproxy: HARD-STOP — checked-out HEAD ($head) != locked commit ($commit)" >&2
    exit 1
  fi

  # Never modify the cached upstream checkout. git archive gives the exact commit in a disposable
  # tree and substitutes the release tag into pkg/types/version.go via upstream's export-subst.
  # The exact x/crypto update is then resolved with the locked Go toolchain and authenticated by
  # the Go checksum database. The resulting go.mod/go.sum pair is itself hash-pinned, so an
  # unexpected module-graph change fails before compilation.
  local build_dir
  build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ntfsmac-gvproxy.XXXXXX")" || {
    echo "build-gvproxy: HARD-STOP — could not create temporary build directory" >&2
    exit 1
  }
  cleanup_gvproxy_build_dir() { rm -rf -- "$build_dir"; }
  trap cleanup_gvproxy_build_dir EXIT

  if ! git -C "$CACHE_DIR" archive "$commit" | tar -x -C "$build_dir"; then
    echo "build-gvproxy: HARD-STOP — could not export locked source commit" >&2
    exit 1
  fi

  echo "build-gvproxy: applying locked golang.org/x/crypto $x_crypto_version security overlay"
  if ! (cd "$build_dir" && \
        GOFLAGS=-mod=mod go_with_locked_toolchain get "golang.org/x/crypto@$x_crypto_version" && \
        GOFLAGS=-mod=mod go_with_locked_toolchain mod vendor); then
    echo "build-gvproxy: HARD-STOP — could not resolve the locked Go security overlay" >&2
    exit 1
  fi

  local resolved_x_crypto actual_overlay_sha256
  resolved_x_crypto="$(cd "$build_dir" && GOFLAGS=-mod=mod go_with_locked_toolchain list -m -f '{{.Version}}' golang.org/x/crypto)" || {
    echo "build-gvproxy: HARD-STOP — could not inspect the resolved x/crypto version" >&2
    exit 1
  }
  if [[ "$resolved_x_crypto" != "$x_crypto_version" ]]; then
    echo "build-gvproxy: HARD-STOP — resolved x/crypto $resolved_x_crypto != locked $x_crypto_version" >&2
    exit 1
  fi
  actual_overlay_sha256="$(cd "$build_dir" && shasum -a 256 go.mod go.sum | shasum -a 256 | awk '{print $1}')"
  if [[ "$actual_overlay_sha256" != "$expected_overlay_sha256" ]]; then
    echo "build-gvproxy: HARD-STOP — Go overlay hash mismatch (expected $expected_overlay_sha256, got $actual_overlay_sha256)" >&2
    exit 1
  fi

  local candidate_bin
  candidate_bin="$build_dir/gvproxy"
  echo "build-gvproxy: building gvproxy @ $commit with x/crypto $x_crypto_version"
  if ! (cd "$build_dir" && go_with_locked_toolchain build \
        -ldflags "-X github.com/containers/gvisor-tap-vsock/pkg/types.gitVersion=$version" \
        -o "$candidate_bin" ./cmd/gvproxy); then
    echo "build-gvproxy: HARD-STOP — source build failed" >&2
    exit 1
  fi
  local built_x_crypto
  built_x_crypto="$(go_with_locked_toolchain version -m "$candidate_bin" | awk '$2 == "golang.org/x/crypto" { print $3 }')"
  if [[ "$built_x_crypto" != "$x_crypto_version" ]]; then
    echo "build-gvproxy: HARD-STOP — built binary embeds x/crypto $built_x_crypto, expected $x_crypto_version" >&2
    exit 1
  fi
  if [[ "$("$candidate_bin" --version 2>&1)" != "gvproxy version $version" ]]; then
    echo "build-gvproxy: HARD-STOP — built binary does not report locked gvproxy version $version" >&2
    exit 1
  fi
  cp "$candidate_bin" "$BIN_DIR/gvproxy"
  chmod +x "$BIN_DIR/gvproxy"
  cleanup_gvproxy_build_dir
  trap - EXIT
  echo "build-gvproxy: done — $BIN_DIR/gvproxy"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
