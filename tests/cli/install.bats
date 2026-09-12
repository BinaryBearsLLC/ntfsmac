#!/usr/bin/env bats
# tests/cli/install.bats — 2-install-sh acceptance (PLAN.md §6, L4, L7, L10).
# Runs against a temp prefix using this repo's real, already-built vendor/bin artifacts.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/install.sh"
  PREFIX_DIR="$(mktemp -d)"
  export NTFSMAC_PREFIX="$PREFIX_DIR"
  # Scratch, never the real /usr/local/bin — a test run must never symlink into shared system
  # state. Nested one level so link_into_path()'s mkdir -p is actually exercised.
  SYMLINK_DIR="$(mktemp -d)/bin"
  export NTFSMAC_PATH_SYMLINK="$SYMLINK_DIR/ntfsmac"
  export NTFSMAC_SKIP_ROOT_CHECK=1
  export NTFSMAC_RUNTIME_HOME_OVERRIDE="$PREFIX_DIR/runtime-home"
  EXPECTED_RELEASE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")"
  EXPECTED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$REPO_ROOT/gui/Info.plist")"
}

teardown() {
  rm -rf "$PREFIX_DIR" "$(dirname "$SYMLINK_DIR")"
}

@test "installs into the temp prefix with the expected bin/libexec layout" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -x "$PREFIX_DIR/bin/anylinuxfs" ]
  [ -x "$PREFIX_DIR/bin/ntfsmac" ]
  [ -x "$PREFIX_DIR/libexec/gvproxy" ]
  [ -x "$PREFIX_DIR/libexec/vmnet-helper" ]
  [ -x "$PREFIX_DIR/libexec/vmproxy" ]
  [ -x "$PREFIX_DIR/libexec/init-rootfs" ]
  [ -f "$PREFIX_DIR/lib/modules.squashfs" ]
  [ -x "$PREFIX_DIR/libexec/ntfsmac/commands/mount.sh" ]
  [ -x "$PREFIX_DIR/libexec/ntfsmac/commands/copy.sh" ]
  [ -x "$PREFIX_DIR/libexec/ntfsmac/commands/verify.sh" ]
  [ -x "$PREFIX_DIR/libexec/ntfsmac/commands/filesystem.sh" ]
  [ -x "$PREFIX_DIR/libexec/ntfsmac/commands/opengui.sh" ]
  [ -f "$PREFIX_DIR/libexec/ntfsmac/lib/version.sh" ]
  [ -f "$PREFIX_DIR/libexec/ntfsmac/pf/ntfsmac.anchor.tmpl" ]
  [ -f "$PREFIX_DIR/libexec/ntfsmac/lib/product-info.plist" ]
  [ -f "$PREFIX_DIR/lib/ntfsmac-runtime/SHA256SUMS" ]
  [ -f "$PREFIX_DIR/lib/ntfsmac-runtime/oci/index.json" ]
  [ -f "$PREFIX_DIR/lib/ntfsmac-runtime/apks/bash-5.3.9-r1.apk" ]
  run diff -qr "$REPO_ROOT/vendor/runtime" "$PREFIX_DIR/lib/ntfsmac-runtime"
  [ "$status" -eq 0 ]
  local installed_runtime
  installed_runtime="$(cd "$PREFIX_DIR/lib/ntfsmac-runtime" && pwd -P)"
  run "$REPO_ROOT/vendor/bin/init-rootfs" -verify-offline-runtime "$installed_runtime"
  [ "$status" -eq 0 ]
}

@test "offline runtime update replaces the complete artifact set without retaining stale files" {
  mkdir -p "$PREFIX_DIR/lib/ntfsmac-runtime/apks"
  printf 'stale\n' > "$PREFIX_DIR/lib/ntfsmac-runtime/apks/removed-from-new-release.apk"
  printf 'old-manifest\n' > "$PREFIX_DIR/lib/ntfsmac-runtime/SHA256SUMS"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -e "$PREFIX_DIR/lib/ntfsmac-runtime/apks/removed-from-new-release.apk" ]
  run diff -qr "$REPO_ROOT/vendor/runtime" "$PREFIX_DIR/lib/ntfsmac-runtime"
  [ "$status" -eq 0 ]
}

@test "offline runtime update keeps the installed set unchanged when the source is corrupt" {
  local fixture_root installed_before
  fixture_root="$BATS_TEST_TMPDIR/corrupt-source"
  installed_before="$BATS_TEST_TMPDIR/installed-before"
  mkdir -p "$fixture_root/vendor/bin"
  cp "$REPO_ROOT/vendor/bin/init-rootfs" "$fixture_root/vendor/bin/init-rootfs"
  cp -R "$REPO_ROOT/vendor/runtime" "$fixture_root/vendor/runtime"
  printf 'tampered\n' >> "$fixture_root/vendor/runtime/entrypoint.sh"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  cp -R "$PREFIX_DIR/lib/ntfsmac-runtime" "$installed_before"

  run bash -c 'source "$1"; install_offline_runtime "$2"' _ "$SCRIPT" "$fixture_root"

  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
  run diff -qr "$installed_before" "$PREFIX_DIR/lib/ntfsmac-runtime"
  [ "$status" -eq 0 ]
}

@test "offline runtime update keeps the installed set unchanged when the source payload is missing" {
  local fixture_root installed_before
  fixture_root="$BATS_TEST_TMPDIR/missing-source"
  installed_before="$BATS_TEST_TMPDIR/missing-installed-before"
  mkdir -p "$fixture_root/vendor/bin"
  cp "$REPO_ROOT/vendor/bin/init-rootfs" "$fixture_root/vendor/bin/init-rootfs"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  cp -R "$PREFIX_DIR/lib/ntfsmac-runtime" "$installed_before"

  run bash -c 'source "$1"; install_offline_runtime "$2"' _ "$SCRIPT" "$fixture_root"

  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
  run diff -qr "$installed_before" "$PREFIX_DIR/lib/ntfsmac-runtime"
  [ "$status" -eq 0 ]
}

@test "installed CLI version comes from the copied canonical app Info.plist" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run cmp "$REPO_ROOT/gui/Info.plist" "$PREFIX_DIR/libexec/ntfsmac/lib/product-info.plist"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/ntfsmac" diagnose --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"ntfsmac_version\":\"$EXPECTED_RELEASE\""* ]]
  [[ "$output" == *"\"build_version\":\"$EXPECTED_BUILD\""* ]]
}

@test "symlinks ntfsmac onto an already-on-PATH directory automatically" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -L "$NTFSMAC_PATH_SYMLINK" ]
  [ "$(readlink "$NTFSMAC_PATH_SYMLINK")" = "$PREFIX_DIR/bin/ntfsmac" ]
  [[ "$output" == *"linked $NTFSMAC_PATH_SYMLINK"* ]]
}

@test "self-elevates via sudo only when the prefix/symlink dir actually isn't writable" {
  unset NTFSMAC_SKIP_ROOT_CHECK
  local stub_dir
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/sudo" <<STUB
#!/bin/bash
echo "\$@" >> "$stub_dir/sudo.calls"
exit 0
STUB
  chmod +x "$stub_dir/sudo"
  # A writable prefix + writable symlink dir (both true here, both scratch mktemp dirs) must
  # never trigger a password prompt.
  PATH="$stub_dir:$PATH" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$stub_dir/sudo.calls" ]
  rm -rf "$stub_dir"
}

@test "no com.apple.quarantine xattr survives on any installed binary" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run ! xattr -p com.apple.quarantine "$PREFIX_DIR/bin/anylinuxfs" >/dev/null 2>&1
  run ! xattr -p com.apple.quarantine "$PREFIX_DIR/libexec/gvproxy" >/dev/null 2>&1
}

@test "runtime update atomically replaces the signed executable inode" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local old_inode
  old_inode="$(stat -f %i "$PREFIX_DIR/bin/anylinuxfs")"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(stat -f %i "$PREFIX_DIR/bin/anylinuxfs")" != "$old_inode" ]
  run cmp "$REPO_ROOT/vendor/bin/anylinuxfs" "$PREFIX_DIR/bin/anylinuxfs"
  [ "$status" -eq 0 ]
  run codesign --verify --strict "$PREFIX_DIR/bin/anylinuxfs"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/anylinuxfs" --version
  [ "$status" -eq 0 ]
  [[ "$output" == anylinuxfs* ]]
}

@test "privileged update repairs only real vmproxy cache files for the invoking user" {
  local runtime="$NTFSMAC_RUNTIME_HOME_OVERRIDE/.anylinuxfs/pinned-runtime"
  mkdir -p "$runtime/rootfs"
  printf 'old-vmproxy\n' > "$runtime/rootfs/vmproxy"
  chmod 755 "$runtime/rootfs/vmproxy"

  NTFSMAC_INSTALL_EUID_OVERRIDE=0 \
  NTFSMAC_INVOKING_UID_OVERRIDE="$(id -u)" \
  NTFSMAC_INVOKING_GID_OVERRIDE="$(id -g)" \
    run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"repaired ownership for 1 runtime cache file(s)"* ]]
  [ "$(stat -f %u "$runtime/rootfs/vmproxy")" -eq "$(id -u)" ]
  [ "$(stat -f %g "$runtime/rootfs/vmproxy")" -eq "$(id -g)" ]
}

@test "runtime ownership repair refuses symlinked cache components" {
  local outside runtime_root
  outside="$(mktemp -d)"
  printf 'outside\n' > "$outside/vmproxy"
  runtime_root="$NTFSMAC_RUNTIME_HOME_OVERRIDE/.anylinuxfs"
  mkdir -p "$runtime_root"
  ln -s "$outside" "$runtime_root/redirected-runtime"

  NTFSMAC_INSTALL_EUID_OVERRIDE=0 \
  NTFSMAC_INVOKING_UID_OVERRIDE="$(id -u)" \
  NTFSMAC_INVOKING_GID_OVERRIDE="$(id -g)" \
    run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" != *"repaired ownership"* ]]
  [ -L "$runtime_root/redirected-runtime" ]
  [ "$(cat "$outside/vmproxy")" = "outside" ]
  rm -rf "$outside"
}

@test "NTFSMAC_REPO defaults to the BinaryBears release repository" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BinaryBearsLLC/ntfsmac"* ]]
  run grep -c "YOURUSERNAME" "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "NTFSMAC_REPO override is respected" {
  NTFSMAC_REPO="someoneelse/fork" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"someoneelse/fork"* ]]
}

@test "refuses to install on a non-arm64 host" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/uname" <<'STUB'
#!/bin/bash
[[ "$1" == "-m" ]] && echo "x86_64" || echo "Darwin"
STUB
  chmod +x "$stub_dir/uname"
  PATH="$stub_dir:$PATH" run "$SCRIPT"
  rm -rf "$stub_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"arm64"* ]]
  [ ! -e "$PREFIX_DIR/bin/anylinuxfs" ]
}

@test "ntfsmac dispatcher routes diagnostics and verified-copy commands" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/ntfsmac" diagnose --json
  [ "$status" -eq 0 ]
  [[ "$output" == \{*\} ]]
  [[ "$output" == *'"diagnostic_schema":6'* ]]
  [[ "$output" == *"\"ntfsmac_version\":\"$EXPECTED_RELEASE\""* ]]

  printf 'installed-dispatch\n' > "$PREFIX_DIR/source.txt"
  run "$PREFIX_DIR/bin/ntfsmac" copy --verify "$PREFIX_DIR/source.txt" "$PREFIX_DIR/destination.txt"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/ntfsmac" verify "$PREFIX_DIR/source.txt" "$PREFIX_DIR/destination.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SHA-256 manifest match"* ]]
}

@test "ntfsmac help lists every real command, none left off" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/ntfsmac" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"mount "* ]]
  [[ "$output" == *"unmount "* ]]
  [[ "$output" == *"copy --verify"* ]]
  [[ "$output" == *"filesystem <device>"* ]]
  [[ "$output" == *"verify "* ]]
  [[ "$output" == *"diagnose"* ]]
  [[ "$output" == *"opengui"* ]]
  [[ "$output" == *"uninstall"* ]]
}

@test "ntfsmac mount help reflects NTFS and ext support" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/ntfsmac" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"NTFS"* ]]
  [[ "$output" == *"ext"* ]]
}

@test "ntfsmac with no args and --help both show the same help" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/ntfsmac"
  [ "$status" -eq 0 ]
  [[ "$output" == *"commands:"* ]]
  run "$PREFIX_DIR/bin/ntfsmac" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"commands:"* ]]
}

@test "ntfsmac with an unknown command exits non-zero and still shows help" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$PREFIX_DIR/bin/ntfsmac" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"commands:"* ]]
}
