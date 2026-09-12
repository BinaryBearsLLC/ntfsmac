#!/bin/bash
# Shared Alpine runtime contract for build, mount, and diagnostics.
#
# Callers source build/lib/lock.sh first, then call runtime_alpine_load. The exact runtime image,
# cache directory, and rootfs marker are all derived from sources.lock; none may float independently.
# The cache directory is versioned so upgrades and rollbacks are side-by-side and never delete an
# existing ~/.anylinuxfs/alpine cache created by older releases.

runtime_alpine_load() {
  if ! command -v lock_get >/dev/null 2>&1; then
    echo "runtime-alpine: lock_get is unavailable (source build/lib/lock.sh first)" >&2
    return 1
  fi

  local tag digest commit digest_hex base_packages_sha packages_sha apks_sha offline_sha package_hash
  tag="$(lock_get ALPINE_TAG)" || return 1
  digest="$(lock_get ALPINE_DIGEST)" || return 1
  commit="$(lock_get ANYLINUXFS_COMMIT)" || return 1
  base_packages_sha="$(lock_get ALPINE_BASE_PACKAGES_SHA256)" || return 1
  packages_sha="$(lock_get ALPINE_PACKAGES_SHA256)" || return 1
  apks_sha="$(lock_get ALPINE_APKS_SHA256)" || return 1

  offline_sha="$(lock_get OFFLINE_RUNTIME_SHA256)" || return 1

  case "$tag" in
    TODO-UNRESOLVED)
      echo "runtime-alpine: HARD-STOP — ALPINE_TAG is unresolved in sources.lock" >&2
      return 1
      ;;
    ''|*[!A-Za-z0-9._-]*)
      echo "runtime-alpine: HARD-STOP — invalid ALPINE_TAG in sources.lock" >&2
      return 1
      ;;
  esac
  case "$digest" in
    TODO-UNRESOLVED)
      echo "runtime-alpine: HARD-STOP — ALPINE_DIGEST is unresolved in sources.lock" >&2
      return 1
      ;;
    sha256:*) digest_hex="${digest#sha256:}" ;;
    *)
      echo "runtime-alpine: HARD-STOP — ALPINE_DIGEST must be a sha256 digest" >&2
      return 1
      ;;
  esac
  if [[ ${#digest_hex} -ne 64 ]] || [[ "$digest_hex" == *[!0-9a-f]* ]]; then
    echo "runtime-alpine: HARD-STOP — ALPINE_DIGEST must contain 64 lowercase hexadecimal characters" >&2
    return 1
  fi
  if [[ "$commit" == "TODO-UNRESOLVED" ]]; then
    echo "runtime-alpine: HARD-STOP — ANYLINUXFS_COMMIT is unresolved in sources.lock" >&2
    return 1
  fi
  if [[ ${#commit} -ne 40 ]] || [[ "$commit" == *[!0-9a-f]* ]]; then
    echo "runtime-alpine: HARD-STOP — ANYLINUXFS_COMMIT must contain 40 lowercase hexadecimal characters" >&2
    return 1
  fi
  for package_hash in "$base_packages_sha" "$packages_sha" "$apks_sha" "$offline_sha"; do
    if [[ ${#package_hash} -ne 64 ]] || [[ "$package_hash" == *[!0-9a-f]* ]]; then
      echo "runtime-alpine: HARD-STOP — Alpine runtime lock hashes must contain 64 lowercase hexadecimal characters" >&2
      return 1
    fi
  done

  # Revision 5 initializes exclusively from the bundled, verified payload. Its identity is part
  # of the cache key so older online runtimes remain available for rollback but cannot be reused.
  ALPINE_RUNTIME_REVISION="5"
  ALPINE_RUNTIME_TAG="$tag"
  ALPINE_RUNTIME_DIGEST="$digest"
  ALPINE_BASE_PACKAGES_SHA256="$base_packages_sha"
  ALPINE_PACKAGES_SHA256="$packages_sha"
  ALPINE_APKS_SHA256="$apks_sha"
  OFFLINE_RUNTIME_SHA256="$offline_sha"
  # Retain the immutable upstream identity while importing its verified local OCI copy.
  ALPINE_RUNTIME_REF="docker.io/library/alpine@${digest}"
  ALPINE_RUNTIME_BASE_DIR="alpine-${tag}-${digest_hex:0:12}-${commit:0:12}-${packages_sha:0:12}-${apks_sha:0:12}-${offline_sha:0:12}-r${ALPINE_RUNTIME_REVISION}"
  ALPINE_RUNTIME_VERSION="ntfsmac-alpine-v${ALPINE_RUNTIME_REVISION}|tag=${tag}|digest=${digest}|anylinuxfs=${commit}|base_packages=${base_packages_sha}|packages=${packages_sha}|apks=${apks_sha}|offline=${offline_sha}"
  export ALPINE_RUNTIME_TAG ALPINE_RUNTIME_DIGEST ALPINE_RUNTIME_REF
  export ALPINE_BASE_PACKAGES_SHA256 ALPINE_PACKAGES_SHA256 ALPINE_APKS_SHA256 OFFLINE_RUNTIME_SHA256
  export ALPINE_RUNTIME_BASE_DIR ALPINE_RUNTIME_VERSION ALPINE_RUNTIME_REVISION
}

runtime_alpine_cache_path() {
  local runtime_home="$1"
  printf '%s/.anylinuxfs/%s\n' "$runtime_home" "$ALPINE_RUNTIME_BASE_DIR"
}

# Prints one fixed, privacy-safe state token. It never prints paths or cache contents.
runtime_alpine_cache_state() {
  local runtime_home="$1" base marker fstab base_packages_marker packages_marker apks_marker
  base="$(runtime_alpine_cache_path "$runtime_home")"

  if [[ ! -e "$base" && ! -L "$base" ]]; then
    if [[ -e "$runtime_home/.anylinuxfs/alpine" || -L "$runtime_home/.anylinuxfs/alpine" ]]; then
      printf 'migration_available\n'
    else
      printf 'not_initialized\n'
    fi
    return 0
  fi
  if [[ -L "$base" || ! -d "$base" ]]; then
    printf 'invalid\n'
    return 0
  fi

  marker="$base/rootfs.ver"
  if [[ ! -f "$marker" ]]; then
    printf 'incomplete\n'
    return 0
  fi
  if [[ "$(tr -d '\r\n' < "$marker" 2>/dev/null)" != "$ALPINE_RUNTIME_VERSION" ]]; then
    printf 'mismatch\n'
    return 0
  fi

  base_packages_marker="$base/rootfs/etc/ntfsmac-alpine-base-packages.sha256"
  packages_marker="$base/rootfs/etc/ntfsmac-alpine-packages.sha256"
  apks_marker="$base/rootfs/etc/ntfsmac-alpine-apks.sha256"
  if [[ ! -f "$base_packages_marker" || ! -f "$packages_marker" || ! -f "$apks_marker" ]] ||
     [[ "$(tr -d '\r\n' < "$base_packages_marker" 2>/dev/null)" != "$ALPINE_BASE_PACKAGES_SHA256" ]] ||
     [[ "$(tr -d '\r\n' < "$packages_marker" 2>/dev/null)" != "$ALPINE_PACKAGES_SHA256" ]] ||
     [[ "$(tr -d '\r\n' < "$apks_marker" 2>/dev/null)" != "$ALPINE_APKS_SHA256" ]]; then
    printf 'incomplete\n'
    return 0
  fi

  for required in bin/bash usr/bin/ntfs-3g.probe usr/bin/ntfsinfo usr/sbin/rpc.nfsd usr/local/bin/entrypoint.sh vmproxy; do
    if [[ ! -e "$base/rootfs/$required" ]]; then
      printf 'incomplete\n'
      return 0
    fi
  done
  fstab="$base/rootfs/etc/fstab"
  if [[ ! -f "$fstab" ]] || ! grep -q 'rpc_pipefs' "$fstab" || ! grep -q 'nfsd' "$fstab"; then
    printf 'incomplete\n'
    return 0
  fi

  printf 'initialized\n'
}

runtime_alpine_preserve_cache() {
  local base="$1" stamp destination suffix=0
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  destination="${base}.preserved-${stamp}"
  while [[ -e "$destination" || -L "$destination" ]]; do
    suffix=$((suffix + 1))
    destination="${base}.preserved-${stamp}-${suffix}"
  done
  if ! mv -- "$base" "$destination"; then
    echo "mount: FATAL — could not preserve an incompatible Alpine runtime cache; refusing to overwrite it" >&2
    return 1
  fi
  echo "mount: preserved the incompatible Alpine runtime cache; a fresh pinned cache will be initialized side-by-side" >&2
}

# Prepares only the application-owned cache immediately before a mount. Existing caches are moved,
# never removed. New/legacy caches are left untouched until anylinuxfs performs the related mount
# initialization, so merely installing, diagnosing, or opening Settings never initializes the guest.
runtime_alpine_prepare_cache() {
  local runtime_home="$1" state base
  state="$(runtime_alpine_cache_state "$runtime_home")" || return 1
  base="$(runtime_alpine_cache_path "$runtime_home")"

  case "$state" in
    initialized)
      echo "mount: reusing pinned Alpine runtime ${ALPINE_RUNTIME_TAG} (${ALPINE_RUNTIME_DIGEST})" >&2
      ;;
    not_initialized)
      echo "mount: first run — initializing bundled Alpine offline ${ALPINE_RUNTIME_TAG} (one-time, ~1-2 min)..." >&2
      ;;
    migration_available)
      echo "mount: legacy Alpine cache detected and preserved; initializing pinned Alpine ${ALPINE_RUNTIME_TAG} side-by-side for safe rollback" >&2
      ;;
    mismatch|incomplete|invalid)
      runtime_alpine_preserve_cache "$base" || return 1
      echo "mount: initializing pinned Alpine ${ALPINE_RUNTIME_TAG}; interrupted runs can be retried without touching preserved caches" >&2
      ;;
    *)
      echo "mount: FATAL — unknown Alpine runtime cache state" >&2
      return 1
      ;;
  esac
}
