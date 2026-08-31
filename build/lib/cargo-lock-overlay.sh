#!/bin/bash
# build/lib/cargo-lock-overlay.sh — apply reviewed crate updates to disposable build copies.
#
# anylinuxfs is an upstream-pinned submodule. ntfsmac never edits it in place; security updates
# that do not yet have a suitable upstream-only commit are resolved in the scratch build tree.
# Every selected crate version is exact, and every resulting Cargo.lock is byte-hash pinned so
# Cargo cannot silently choose a different compatible graph on a later build.

cargo_lock_package_versions() {
  local lock_file="$1" package="$2"
  awk -v target="$package" '
    /^\[\[package\]\]$/ { name = ""; next }
    /^name = "/ {
      name = $0
      sub(/^name = "/, "", name)
      sub(/"$/, "", name)
      next
    }
    /^version = "/ && name == target {
      version = $0
      sub(/^version = "/, "", version)
      sub(/"$/, "", version)
      print version
    }
  ' "$lock_file"
}

cargo_apply_lock_overlay() {
  local crate_dir="$1" expected_hash_key="$2"
  local lock_file="$crate_dir/Cargo.lock"
  local anyhow_version expected_hash actual_hash versions version

  if [[ ! -f "$crate_dir/Cargo.toml" || ! -f "$lock_file" ]]; then
    echo "cargo-lock-overlay: HARD-STOP — Cargo manifest or lock missing in $crate_dir" >&2
    return 1
  fi

  anyhow_version="$(lock_get CARGO_ANYHOW_VERSION)" || {
    echo "cargo-lock-overlay: HARD-STOP — CARGO_ANYHOW_VERSION missing from sources.lock" >&2
    return 1
  }
  expected_hash="$(lock_get "$expected_hash_key")" || {
    echo "cargo-lock-overlay: HARD-STOP — $expected_hash_key missing from sources.lock" >&2
    return 1
  }
  if [[ ! "$anyhow_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ||
        ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]]; then
    echo "cargo-lock-overlay: HARD-STOP — malformed crate version or lock hash" >&2
    return 1
  fi

  versions="$(cargo_lock_package_versions "$lock_file" anyhow)"
  if [[ -n "$versions" ]]; then
    if ! rust_with_locked_toolchain cargo update --manifest-path "$crate_dir/Cargo.toml" \
          -p anyhow --precise "$anyhow_version"; then
      echo "cargo-lock-overlay: HARD-STOP — could not resolve anyhow $anyhow_version" >&2
      return 1
    fi
    versions="$(cargo_lock_package_versions "$lock_file" anyhow)"
    while IFS= read -r version; do
      if [[ "$version" != "$anyhow_version" ]]; then
        echo "cargo-lock-overlay: HARD-STOP — resolved anyhow $version, expected $anyhow_version" >&2
        return 1
      fi
    done <<< "$versions"
  fi

  actual_hash="$(shasum -a 256 "$lock_file" | awk '{print $1}')"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "cargo-lock-overlay: HARD-STOP — $(basename "$crate_dir") Cargo.lock hash mismatch (expected $expected_hash, got $actual_hash)" >&2
    return 1
  fi
  echo "cargo-lock-overlay: $(basename "$crate_dir") lock verified ($actual_hash)"
}
