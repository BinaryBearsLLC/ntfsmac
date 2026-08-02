#!/usr/bin/env bats
# tests/build/util-linux.bats — fast acceptance for the static-libblkid fix (tosbaha #1).
# The stager (build-libblkid-static.sh) consumes Homebrew's already-built static archives —
# no source build, no fetch — so it's fast enough to run for real here (just copies .a +
# headers + authors .pc). The real anylinuxfs linkage guard lives in build-all.bats.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/build-libblkid-static.sh"
  # Space-free path, same default as the script itself — the repo path has spaces and
  # pkg-config backslash-escapes them, which breaks the .pc path assertions below.
  STAGE="${NTFSMAC_LIBBLKID_STAGE:-${TMPDIR:-/tmp}/ntfsmac-build/libblkid-static}"
}

@test "build-libblkid-static.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

# Skip the stager-run tests on a machine without Homebrew util-linux (e.g. CI without the
# build dep installed) rather than failing — they assert the stager's real output, which
# only exists where the build dep is present. The preflight test covers the dep's presence.
maybe_skip_no_brew_util_linux() {
  command -v brew >/dev/null 2>&1 || skip "brew not installed"
  local prefix
  prefix="$(brew --prefix util-linux 2>/dev/null)" || true
  [[ -n "$prefix" && -f "$prefix/lib/libblkid.a" ]] || skip "Homebrew util-linux libblkid.a not present"
}

@test "stager produces a dylib-free stage with libblkid.a + libuuid.a + .pc files" {
  maybe_skip_no_brew_util_linux
  NTFSMAC_LIBBLKID_STAGE="$STAGE" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STAGE/lib/libblkid.a" ]
  [ -f "$STAGE/lib/libuuid.a" ]
  # No dylib may be present in the stage — this is the whole point: with only .a here,
  # -lblkid resolves to the static archive for certain.
  run find "$STAGE/lib" -name '*.dylib'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "staged blkid.pc pulls libuuid statically (Requires.private: uuid)" {
  maybe_skip_no_brew_util_linux
  NTFSMAC_LIBBLKID_STAGE="$STAGE" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STAGE/lib/pkgconfig/blkid.pc" ]
  [ -f "$STAGE/lib/pkgconfig/uuid.pc" ]
  run grep -E '^Requires\.private: uuid' "$STAGE/lib/pkgconfig/blkid.pc"
  [ "$status" -eq 0 ]
  # The staged .pc must point at the stage dir (not Homebrew's), so the linker can't
  # fall back to Homebrew's dylib. The .pc uses prefix=$STAGE then libdir=${prefix}/lib,
  # so assert on the prefix line (the literal stage path lives there, not in libdir=).
  run grep -E '^prefix=' "$STAGE/lib/pkgconfig/blkid.pc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$STAGE"* ]]
}

@test "pkg-config --static --libs blkid resolves to the staged static archives" {
  maybe_skip_no_brew_util_linux
  NTFSMAC_LIBBLKID_STAGE="$STAGE" run "$SCRIPT"
  [ "$status" -eq 0 ]
  run env PKG_CONFIG_PATH="$STAGE/lib/pkgconfig" pkg-config --static --libs blkid
  [ "$status" -eq 0 ]
  # Must reference the stage libdir and -lblkid (and transitively -luuid), proving the
  # static resolution path is wired through pkg-config the way libblkid-rs-sys expects.
  [[ "$output" == *"$STAGE/lib"* ]]
  [[ "$output" == *"-lblkid"* ]]
  [[ "$output" == *"-luuid"* ]]
}