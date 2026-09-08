#!/usr/bin/env bats

@test "rootfs setup stages the signed vendor artifact rather than unsigned compiler output" {
  local repo_root
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/cache/init-rootfs/bin" "$BATS_TEST_TMPDIR/bin"
  cp /usr/bin/false "$BATS_TEST_TMPDIR/cache/init-rootfs/bin/init-rootfs"
  cp /usr/bin/true "$BATS_TEST_TMPDIR/bin/init-rootfs"
  run bash -c '
    source "$1/build/init-rootfs.sh"
    CACHE_DIR="$2/cache"
    BIN_DIR="$2/bin"
    ROOTFS_HOME="$2/home"
    run_init_rootfs unused test-base
    cmp "$BIN_DIR/init-rootfs" "$CACHE_DIR/run/libexec/init-rootfs"
  ' _ "$repo_root" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}
