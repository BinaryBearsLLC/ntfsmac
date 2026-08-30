#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "init-rootfs ignores optional registry metadata from the user home" {
  local scratch
  scratch="$BATS_TEST_TMPDIR/init-rootfs"
  mkdir -p "$scratch"
  cp "$REPO_ROOT/vendor/src/anylinuxfs/init-rootfs/main.go" "$scratch/main.go"

  run env REPO_ROOT="$REPO_ROOT" SCRATCH="$scratch" bash -c '
    set -euo pipefail
    source "$REPO_ROOT/build/lib/lock.sh"
    source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
    source "$REPO_ROOT/build/lib/patch-runtime-alpine.sh"
    runtime_alpine_load
    patch_init_rootfs_runtime_alpine "$SCRATCH" "$REPO_ROOT/build/alpine-apks.lock"
    grep -F "RegistriesDirPath: filepath.Join(cfg.ImageBasePath, \".ntfsmac-empty-registries.d\")" "$SCRATCH/main.go"
    test "$(grep -c "RegistriesDirPath:" "$SCRATCH/main.go")" -eq 1
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"isolated registry metadata"* ]]
}
