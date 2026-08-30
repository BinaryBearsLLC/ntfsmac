#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=../../build/lib/lock.sh
  source "$REPO_ROOT/build/lib/lock.sh"
  # shellcheck source=../../cli/lib/runtime-alpine.sh
  source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
  # shellcheck source=../../build/init-rootfs.sh
  source "$REPO_ROOT/build/init-rootfs.sh"
  runtime_alpine_load
  ARTIFACT_CACHE="$APK_CACHE_ROOT/$ALPINE_APKS_SHA256"
}

ensure_locked_artifacts() {
  verify_apk_lock
  verify_apk_artifacts
}

apk_path() {
  local package="$1"
  printf '%s/%s-2026.7.7-r0.apk\n' "$ARTIFACT_CACHE" "$package"
}

@test "ntfs-3g 2026.7.7 APK metadata is one signed aarch64 Alpine build" {
  ensure_locked_artifacts
  local package apk info
  for package in ntfs-3g ntfs-3g-libs ntfs-3g-progs; do
    apk="$(apk_path "$package")"
    [ -f "$apk" ]
    info="$(tar -xOzf "$apk" .PKGINFO 2>/dev/null)"
    [[ "$info" == *"pkgname = $package"* ]]
    [[ "$info" == *"pkgver = 2026.7.7-r0"* ]]
    [[ "$info" == *"arch = aarch64"* ]]
    [[ "$info" == *"origin = ntfs-3g"* ]]
    [[ "$info" == *"commit = 905147fb282a60cd622b45c7421db8a116cf80ab"* ]]
    run bash -c 'tar -tzf "$1" 2>/dev/null | grep -Eq "^\\.SIGN\\.RSA\\.alpine-devel@lists\\.alpinelinux\\.org-.*\\.rsa\\.pub$"' _ "$apk"
    [ "$status" -eq 0 ]
  done
}

@test "the security update keeps ntfsmac probe and inspection tools" {
  ensure_locked_artifacts
  local driver_listing progs_listing
  driver_listing="$(tar -tzf "$(apk_path ntfs-3g)" 2>/dev/null)"
  progs_listing="$(tar -tzf "$(apk_path ntfs-3g-progs)" 2>/dev/null)"
  [[ "$driver_listing" == *"bin/ntfs-3g"* ]]
  [[ "$progs_listing" == *"usr/bin/ntfs-3g.probe"* ]]
  [[ "$progs_listing" == *"usr/bin/ntfsinfo"* ]]
}

@test "the complete ntfs-3g family moves coherently from SONAME 89 to 90" {
  ensure_locked_artifacts
  local driver_info progs_info libs_info library
  driver_info="$(tar -xOzf "$(apk_path ntfs-3g)" .PKGINFO 2>/dev/null)"
  progs_info="$(tar -xOzf "$(apk_path ntfs-3g-progs)" .PKGINFO 2>/dev/null)"
  libs_info="$(tar -xOzf "$(apk_path ntfs-3g-libs)" .PKGINFO 2>/dev/null)"
  [[ "$driver_info" == *"depend = so:libntfs-3g.so.90"* ]]
  [[ "$progs_info" == *"depend = so:libntfs-3g.so.90"* ]]
  [[ "$libs_info" == *"provides = so:libntfs-3g.so.90=90.0.0"* ]]
  [[ "$driver_info$progs_info$libs_info" != *"libntfs-3g.so.89"* ]]

  library="$BATS_TEST_TMPDIR/libntfs-3g.so.90.0.0"
  tar -xOzf "$(apk_path ntfs-3g-libs)" usr/lib/libntfs-3g.so.90.0.0 > "$library" 2>/dev/null
  run /opt/homebrew/opt/llvm/bin/llvm-readelf -d "$library"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Library soname: [libntfs-3g.so.90]"* ]]
  [[ "$output" == *"Shared library: [libc.musl-aarch64.so.1]"* ]]
}
