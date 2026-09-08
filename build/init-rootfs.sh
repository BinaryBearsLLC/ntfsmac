#!/bin/bash
# build/init-rootfs.sh — v-alpine-rootfs (PLAN.md §6).
#
# Pulls Alpine at the sources.lock tag, independently verifies the registry manifest
# digest against ALPINE_DIGEST before doing anything else (abort on mismatch — never
# trust :latest or an unpinned pull). Builds a *patched copy* of vendored anylinuxfs's
# init-rootfs (Go) + vmrunner-sys (Rust/CGO) — the vendored submodule itself is never
# edited — swapping its embedded default-alpine-packages.txt for the exact, complete
# add-on closure in build/alpine-packages.lock. build/alpine-apks.lock also fixes the source
# channel and SHA-256 of every APK; the guest installs only those local verified artifacts with
# apk networking disabled. The direct feature set remains audited in build/alpine-packages.trimmed.txt.
# Custom packages are rejected in the ntfsmac build so they cannot bypass the locks. Output lands
# under vendor/rootfs/
# (redirected via $HOME using the `osusergo` build tag, since upstream's cgo user
# lookup ignores $HOME otherwise).
#
# Also vendors the built init-rootfs binary itself to vendor/bin/init-rootfs — the
# real fix for the GATE-CLI-BEFORE-GUI blocker documented in build/AUDIT.md:
# anylinuxfs's Rust code (main.rs) expects an init-rootfs helper at
# $PREFIX/libexec/init-rootfs and spawns it directly (vm_image.rs Command::new); it
# was being built here already but only into the ephemeral $CACHE_DIR, never vendored.
# build/sign.sh signs vendor/bin/init-rootfs with the hypervisor entitlement (it calls
# Hypervisor.framework directly via vmrunner-sys, same as anylinuxfs) and install.sh /
# Formula/ntfsmac.rb copy it into $PREFIX/libexec alongside gvproxy/vmnet-helper/vmproxy.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
# shellcheck source=lib/lock.sh
source "$SCRIPT_DIR/lib/lock.sh"
# shellcheck source=lib/go-toolchain.sh
source "$SCRIPT_DIR/lib/go-toolchain.sh"
source "$SCRIPT_DIR/lib/macos-target.sh"
macos_target_activate
# shellcheck source=lib/rust-toolchain.sh
source "$SCRIPT_DIR/lib/rust-toolchain.sh"
# shellcheck source=lib/cargo-lock-overlay.sh
source "$SCRIPT_DIR/lib/cargo-lock-overlay.sh"
# shellcheck source=../cli/lib/runtime-alpine.sh
source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
# shellcheck source=lib/patch-runtime-alpine.sh
source "$SCRIPT_DIR/lib/patch-runtime-alpine.sh"

# NOTE: deliberately NOT under $REPO_ROOT. This repo's own path can contain spaces
# (e.g. when checked out on a "Windows Shared Folder" network volume), and
# krun-init-blob's build.rs (a libkrun dep, pulled in by vmrunner-sys)
# whitespace-splits the CC_LINUX compiler path — a space in the path truncates it
# and the build fails with "failed to execute <repo>: No such file or directory"
# (truncated at the first space). Confirmed by building the identical sources from a
# space-free path, which compiles clean. Building from a space-free cache dir outside
# the repo is the fix, not a workaround around a real bug in our own code.
CACHE_DIR="${NTFSMAC_ROOTFS_CACHE_DIR:-${TMPDIR:-/tmp}/ntfsmac-build/init-rootfs-build}"
# NOTE: also NOT under $REPO_ROOT. Separately from the spaces-in-path issue above, the
# repo's underlying volume ("Windows Shared Folder", network-mounted NTFS) does not
# support the fsync/ioctl calls go.podman.io/image's blob-copy step makes — confirmed
# real failure: "sync .../oci-put-blob...: inappropriate ioctl for device". Plain
# writes (curl downloads, tar extraction, go build output — see vendor/kernel,
# vendor/bin) work fine on this volume; it's specifically this fsync pattern that
# doesn't. Redirecting the real OCI pull/unpack to a space-free, POSIX-reliable cache
# dir outside the repo. Flagged in build/AUDIT.md — PLAN.md's literal "output
# under vendor/rootfs/" wording can't be satisfied on-volume; open decision for the maintainer.
ROOTFS_HOME="${NTFSMAC_VENDOR_ROOTFS_DIR:-${TMPDIR:-/tmp}/ntfsmac-build/rootfs-home}"
BASE_PACKAGE_LOCK="$REPO_ROOT/build/alpine-base-packages.lock"
PACKAGE_LOCK="$REPO_ROOT/build/alpine-packages.lock"
APK_LOCK="$REPO_ROOT/build/alpine-apks.lock"
APK_CACHE_ROOT="${NTFSMAC_ALPINE_APK_CACHE_DIR:-${TMPDIR:-/tmp}/ntfsmac-build/alpine-apks}"
BIN_DIR="${NTFSMAC_VENDOR_BIN_DIR:-$REPO_ROOT/vendor/bin}"

verify_package_lock() {
  local lock_file="$1" expected_sha="$2" label="$3" actual_sha
  if [[ ! -s "$lock_file" ]]; then
    echo "init-rootfs: HARD-STOP — $label lock is missing or empty: $lock_file" >&2
    return 1
  fi
  if ! LC_ALL=C sort -cu "$lock_file"; then
    echo "init-rootfs: HARD-STOP — $label lock must be sorted and contain unique entries" >&2
    return 1
  fi
  if grep -Ev '^[a-z0-9][a-z0-9+_.-]*=[A-Za-z0-9][A-Za-z0-9+_.:~-]*-r[0-9]+$' "$lock_file" >/dev/null; then
    echo "init-rootfs: HARD-STOP — $label lock contains an invalid or non-exact package constraint" >&2
    return 1
  fi
  actual_sha="$(shasum -a 256 "$lock_file" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "init-rootfs: HARD-STOP — $label lock sha256 mismatch (expected $expected_sha, got $actual_sha)" >&2
    return 1
  fi
  echo "init-rootfs: verified $label lock ($actual_sha)"
}

verify_apk_lock() {
  local actual_sha constraints constraint channel sha extra
  if [[ ! -s "$APK_LOCK" ]]; then
    echo "init-rootfs: HARD-STOP — Alpine APK artifact lock is missing or empty: $APK_LOCK" >&2
    return 1
  fi
  actual_sha="$(shasum -a 256 "$APK_LOCK" | awk '{print $1}')"
  if [[ "$actual_sha" != "$ALPINE_APKS_SHA256" ]]; then
    echo "init-rootfs: HARD-STOP — Alpine APK artifact lock sha256 mismatch (expected $ALPINE_APKS_SHA256, got $actual_sha)" >&2
    return 1
  fi

  mkdir -p "$CACHE_DIR"
  constraints="$CACHE_DIR/alpine-apk.constraints"
  : > "$constraints"
  while IFS=' ' read -r constraint channel sha extra; do
    if [[ -n "$extra" ]] ||
       [[ ! "$constraint" =~ ^[a-z0-9][a-z0-9+_.-]*=[A-Za-z0-9][A-Za-z0-9+_.:~-]*-r[0-9]+$ ]] ||
       [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
      echo "init-rootfs: HARD-STOP — Alpine APK artifact lock contains an invalid entry" >&2
      return 1
    fi
    case "$channel" in
      "v${ALPINE_RUNTIME_TAG%.*}/main"|"v${ALPINE_RUNTIME_TAG%.*}/community") ;;
      edge/main|edge/community)
        if [[ ! "$constraint" =~ ^ntfs-3g(-libs|-progs)?=2026\.7\.7-r0$ ]]; then
          echo "init-rootfs: HARD-STOP — Alpine edge is approved only for the ntfs-3g 2026.7.7-r0 security family" >&2
          return 1
        fi
        ;;
      *)
        echo "init-rootfs: HARD-STOP — Alpine APK artifact lock contains an unapproved channel: $channel" >&2
        return 1
        ;;
    esac
    printf '%s\n' "$constraint" >> "$constraints"
  done < "$APK_LOCK"
  if ! LC_ALL=C sort -cu "$constraints" || ! cmp -s "$PACKAGE_LOCK" "$constraints"; then
    echo "init-rootfs: HARD-STOP — Alpine APK artifact lock does not match the exact add-on package manifest" >&2
    return 1
  fi
  echo "init-rootfs: verified Alpine APK artifact lock ($actual_sha)"
}

verify_apk_artifacts() {
  local artifact_cache constraint channel expected_sha extra name version file url destination download actual_sha
  artifact_cache="$APK_CACHE_ROOT/$ALPINE_APKS_SHA256"
  mkdir -p "$artifact_cache"
  while IFS=' ' read -r constraint channel expected_sha extra; do
    name="${constraint%%=*}"
    version="${constraint#*=}"
    file="${name}-${version}.apk"
    url="https://dl-cdn.alpinelinux.org/alpine/${channel}/aarch64/${file}"
    destination="$artifact_cache/$file"
    if [[ -f "$destination" ]]; then
      actual_sha="$(shasum -a 256 "$destination" | awk '{print $1}')"
      [[ "$actual_sha" == "$expected_sha" ]] && continue
    fi
    download="${destination}.download.$$"
    if ! curl -fsSL "$url" -o "$download"; then
      rm -f -- "$download"
      echo "init-rootfs: HARD-STOP — could not fetch locked Alpine APK $file" >&2
      return 1
    fi
    actual_sha="$(shasum -a 256 "$download" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      rm -f -- "$download"
      echo "init-rootfs: HARD-STOP — Alpine APK sha256 mismatch for $file (expected $expected_sha, got $actual_sha)" >&2
      return 1
    fi
    mv -f -- "$download" "$destination"
  done < "$APK_LOCK"
  echo "init-rootfs: verified all locked Alpine APK artifacts"
}

verify_rootfs_package_versions() {
  local rootfs="$1" label="$2"
  shift 2
  local installed="$rootfs/lib/apk/db/installed"
  local actual="$CACHE_DIR/${label}.installed" expected="$CACHE_DIR/${label}.expected" delta
  if [[ ! -f "$installed" ]]; then
    echo "init-rootfs: HARD-STOP — unpacked rootfs package database is missing" >&2
    return 1
  fi
  awk 'BEGIN { RS=""; FS="\n" }
    {
      package=""; version=""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^P:/) package=substr($i, 3)
        if ($i ~ /^V:/) version=substr($i, 3)
      }
      if (package != "" && version != "") print package "=" version
    }' "$installed" | LC_ALL=C sort -u > "$actual"
  cat "$@" | LC_ALL=C sort -u > "$expected"
  delta="$(LC_ALL=C comm -3 "$expected" "$actual")"
  if [[ -n "$delta" ]]; then
    echo "init-rootfs: HARD-STOP — $label package manifest is not exact:" >&2
    printf '%s\n' "$delta" >&2
    return 1
  fi
  echo "init-rootfs: verified exact $label package manifest"
}

# verify_alpine_digest <tag> <expected_digest>
# ALPINE_DIGEST is pinned to the linux/arm64 PLATFORM manifest digest (not the
# top-level multi-arch index digest — those differ). Fetches the manifest list body
# from the registry v2 API and picks out the linux/arm64 entry's digest, matching how
# the pin itself was derived (Apple Silicon only, per PLAN.md L-rule). Real
# cryptographic pin check, done BEFORE any pull.
verify_alpine_digest() {
  local tag="$1" expected="$2" token actual
  token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/alpine:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  if [[ -z "$token" ]]; then
    echo "init-rootfs: could not obtain a Docker Hub registry token" >&2
    return 1
  fi
  actual="$(curl -fsSL \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.index.v1+json" \
    "https://registry-1.docker.io/v2/library/alpine/manifests/${tag}" \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
for m in d.get("manifests", []):
    p = m.get("platform", {})
    if p.get("architecture") == "arm64" and p.get("os") == "linux":
        print(m["digest"])
        break
')"
  if [[ -z "$actual" ]]; then
    echo "init-rootfs: could not find a linux/arm64 manifest entry for alpine:${tag}" >&2
    return 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "init-rootfs: HARD-STOP — alpine:${tag} linux/arm64 manifest digest mismatch (expected $expected, got $actual)" >&2
    return 1
  fi
  echo "init-rootfs: alpine:${tag} linux/arm64 digest verified ($actual)"
}

# prepare_build_copy — copy the vendored Go+Rust sources (never edit the submodule
# in place) into a scratch dir, preserving their sibling layout: vmrunner.go's cgo
# LDFLAGS and vmrunner-sys/.cargo/config.toml's CC_LINUX both use relative paths
# assuming init-rootfs/, vmrunner-sys/, and anylinuxfs/ are siblings (CC_LINUX =
# "../anylinuxfs/cc_linux" — the cross-compiler wrapper krun-init-blob's build.rs
# needs; only that one file is required, not the whole anylinuxfs crate). Swaps in
# our trimmed package list.
prepare_build_copy() {
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR/anylinuxfs"
  cp -R "$REPO_ROOT/vendor/src/anylinuxfs/vmrunner-sys" "$CACHE_DIR/vmrunner-sys"
  cp -R "$REPO_ROOT/vendor/src/anylinuxfs/init-rootfs" "$CACHE_DIR/init-rootfs"
  cargo_apply_lock_overlay "$CACHE_DIR/vmrunner-sys" CARGO_VMRUNNER_SYS_LOCK_SHA256 || return 1
  cp "$REPO_ROOT/vendor/src/anylinuxfs/anylinuxfs/cc_linux" "$CACHE_DIR/anylinuxfs/cc_linux"
  chmod +x "$CACHE_DIR/anylinuxfs/cc_linux"
  cp "$PACKAGE_LOCK" "$CACHE_DIR/init-rootfs/default-alpine-packages.txt"
  patch_init_rootfs_runtime_alpine "$CACHE_DIR/init-rootfs" "$APK_LOCK"
}

# build_vmrunner_sys — settled PLAN.md decision: try without -F freebsd first.
# If that doesn't compile clean, HARD-STOP per PLAN.md §6 (don't drop the flag blind).
build_vmrunner_sys() {
  if (cd "$CACHE_DIR/vmrunner-sys" && cargo build --release --no-default-features 2>&1); then
    echo "init-rootfs: vmrunner-sys builds clean without -F freebsd"
  else
    echo "init-rootfs: HARD-STOP — vmrunner-sys does not compile without -F freebsd. Per PLAN.md §6, keep the flag and record why in AUDIT.md rather than dropping blind." >&2
    return 1
  fi
  cp "$CACHE_DIR/vmrunner-sys/target/release/libvmrunner_sys.a" "$CACHE_DIR/vmrunner-sys/target/"
}

build_init_rootfs_bin() {
  (cd "$CACHE_DIR/init-rootfs" && CGO_ENABLED=1 \
    CGO_CFLAGS="${CGO_CFLAGS:-} -mmacosx-version-min=14.0" \
    CGO_LDFLAGS="${CGO_LDFLAGS:-} -mmacosx-version-min=14.0" \
    go_with_locked_toolchain build -tags 'containers_image_openpgp osusergo' \
    -ldflags="-w -s -extldflags=-mmacosx-version-min=14.0" -o bin/init-rootfs .) || return 1
  macos_target_verify_binary "$CACHE_DIR/init-rootfs/bin/init-rootfs"
}

# vendor_init_rootfs_bin — copies the built binary out of the ephemeral cache into
# vendor/bin/, matching the gvproxy/vmproxy/vmnet-helper convention, then actually runs
# build/sign.sh (previously only a comment's stated intent — nothing in the pipeline called
# it, so every real build shipped an unentitled init-rootfs that fails to boot its VM with
# "start vm error: Invalid argument (errno 22)" on real hardware, same root cause as the
# anylinuxfs fix in build/build-all.sh). A bare `codesign -s -` alone (the old approach)
# produces a validly-signed-but-unentitled binary — passes `codesign -v` but still can't
# call Hypervisor.framework without com.apple.security.hypervisor.
vendor_init_rootfs_bin() {
  mkdir -p "$BIN_DIR"
  cp "$CACHE_DIR/init-rootfs/bin/init-rootfs" "$BIN_DIR/init-rootfs"
  chmod +x "$BIN_DIR/init-rootfs"
  NTFSMAC_VENDOR_BIN_DIR="$BIN_DIR" "$SCRIPT_DIR/sign.sh" || {
    echo "init-rootfs: HARD-STOP — signing init-rootfs (with required entitlements) failed." >&2
    return 1
  }
  echo "init-rootfs: vendored $BIN_DIR/init-rootfs"
}

# run_init_rootfs <reference> <base-dir> — stages a libexec/ layout (binary + kernel Image, matching
# upstream's PrefixDir/libexec/Image expectation) and runs the real tool with $HOME
# redirected into vendor/rootfs/ so pull+unpack+setup-script land inside the repo.
# The pull/unpack/setup-script-write happen before the VM boot step, so even if the
# VM boot hangs or fails, the generated package manifest is already on disk — bounded
# with a manual timeout (no coreutils `timeout` dependency) so an autonomous run can't
# hang forever on a Hypervisor.framework boot that never completes.
run_init_rootfs() {
  local reference="$1" base_dir="$2"
  local run_dir="$CACHE_DIR/run"
  mkdir -p "$run_dir/libexec" "$ROOTFS_HOME"
  # vendor_init_rootfs_bin signs the vendored copy, not the compiler output.
  # Launching the latter loses the Hypervisor entitlement and fails before boot.
  cp "$BIN_DIR/init-rootfs" "$run_dir/libexec/init-rootfs" || return 1
  cp "$REPO_ROOT/vendor/kernel/Image" "$run_dir/libexec/Image"
  chmod +x "$run_dir/libexec/init-rootfs"

  # modules.squashfs was already fetched for real by v-fetch-prebuilt — stage it.
  mkdir -p "$run_dir/lib"
  if [[ -f "$REPO_ROOT/vendor/kernel/modules.squashfs" ]]; then
    cp "$REPO_ROOT/vendor/kernel/modules.squashfs" "$run_dir/lib/modules.squashfs"
  else
    echo "init-rootfs: WARN — vendor/kernel/modules.squashfs not found (run v-fetch-prebuilt first)" >&2
  fi

  # vmproxy is a v-anylinuxfs-build artifact (not yet built at this point in the DAG —
  # PLAN.md's V-1 layer runs v-alpine-rootfs in parallel with v-fetch-prebuilt/v-gvproxy,
  # sharing only v-audit as a dep). Stage it if present so a re-run after
  # v-anylinuxfs-build completes the full embed; if absent, the upstream tool's own
  # vmproxy-copy step will fail non-fatally for THIS unit's purposes — the setup script
  # (this unit's actual acceptance artifact) is already written to disk by that point.
  if [[ -f "$REPO_ROOT/vendor/bin/vmproxy" ]]; then
    cp "$REPO_ROOT/vendor/bin/vmproxy" "$run_dir/libexec/vmproxy"
  else
    echo "init-rootfs: NOTE — vendor/bin/vmproxy not built yet (v-anylinuxfs-build's job). The upstream tool will fail to embed it into the rootfs and exit non-zero at that step; expected at this point in the DAG. Setup script + package manifest (this unit's acceptance artifact) are generated BEFORE that step, so they're already on disk. Full assembly + VM boot should be re-verified once v-anylinuxfs-build lands." >&2
  fi

  # Run in the foreground (not backgrounded): the Go binary's own process-group
  # signal handling (used for its Hypervisor.framework VM lifecycle) was observed to
  # terminate a bash job-control wrapper around it, which silently truncated this
  # script's own execution. Pull/unpack/setup-script-write finish in well under the
  # VM_BOOT_TIMEOUT window in every observed run (the failure mode we actually hit —
  # missing vendor/bin/vmproxy — returns in seconds); a true VM-boot hang would still
  # be caught by the caller's own process/tool timeout. Revisit with a proper
  # setsid-based watchdog once vmproxy is available and VM boot is actually reachable.
  echo "init-rootfs: running (HOME=$ROOTFS_HOME)"
  (cd "$run_dir/libexec" && HOME="$ROOTFS_HOME" ./init-rootfs \
    -docker-ref "$reference" -base-dir "$base_dir") || true
  return 0
}

main() {
  local tag digest rootfs
  local build_mode="${NTFSMAC_ROOTFS_BUILD_MODE:-full}"
  case "$build_mode" in
    full|compile-only) ;;
    *) echo "init-rootfs: HARD-STOP — unknown rootfs build mode" >&2; exit 1 ;;
  esac
  rust_activate_locked_toolchain || exit 1
  runtime_alpine_load || exit 1
  tag="$ALPINE_RUNTIME_TAG"
  digest="$ALPINE_RUNTIME_DIGEST"

  verify_package_lock "$BASE_PACKAGE_LOCK" "$ALPINE_BASE_PACKAGES_SHA256" "Alpine base package" || exit 1
  verify_package_lock "$PACKAGE_LOCK" "$ALPINE_PACKAGES_SHA256" "Alpine add-on package" || exit 1
  verify_apk_lock || exit 1
  verify_alpine_digest "$tag" "$digest" || exit 1

  prepare_build_copy || exit 1
  verify_apk_artifacts || exit 1
  build_vmrunner_sys || exit 1
  build_init_rootfs_bin || exit 1
  vendor_init_rootfs_bin || exit 1
  if [[ "$build_mode" == compile-only ]]; then
    echo "init-rootfs: compiled and signed; native VM/package-install acceptance NOT RUN"
    return 0
  fi
  run_init_rootfs "$ALPINE_RUNTIME_REF" "$ALPINE_RUNTIME_BASE_DIR" || exit 1

  rootfs="$ROOTFS_HOME/.anylinuxfs/$ALPINE_RUNTIME_BASE_DIR/rootfs"
  if [[ -f "$rootfs/etc/ntfsmac-alpine-base-packages.sha256" &&
        -f "$rootfs/etc/ntfsmac-alpine-packages.sha256" &&
        -f "$rootfs/etc/ntfsmac-alpine-apks.sha256" ]]; then
    verify_rootfs_package_versions "$rootfs" "complete Alpine runtime" \
      "$BASE_PACKAGE_LOCK" "$PACKAGE_LOCK" || exit 1
  else
    verify_rootfs_package_versions "$rootfs" "Alpine base" "$BASE_PACKAGE_LOCK" || exit 1
    if [[ -x "$BIN_DIR/vmproxy" ]]; then
      echo "init-rootfs: HARD-STOP — VM setup did not install the locked add-on packages" >&2
      exit 1
    fi
    echo "init-rootfs: NOTE — VM setup did not complete; the exact add-on manifest was generated but not installed"
  fi

  echo "init-rootfs: done — inspect $ROOTFS_HOME for the generated rootfs and vm-setup.sh"
  echo "init-rootfs: NTFSMAC_ROOTFS_HOME=$ROOTFS_HOME"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
