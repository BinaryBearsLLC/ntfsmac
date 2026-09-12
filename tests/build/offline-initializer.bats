#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "offline initializer verifies payload and rejects tampering and path escapes" {
  [ -f "$REPO_ROOT/build/runtime/offline_runtime.go" ]
  local scratch="$BATS_TEST_TMPDIR/adapter"
  mkdir -p "$scratch"
  cp "$REPO_ROOT/build/runtime/offline_runtime"*.go "$scratch/"
  cp "$REPO_ROOT/vendor/runtime/SHA256SUMS" "$scratch/offline-runtime.sha256"
  cat > "$scratch/config.go" <<'GOEOF'
package main
const offlineRuntimeReference = "docker.io/library/alpine@sha256:test"
type Config struct { PrefixDir, SourceReference, RootfsPath string }
GOEOF
  printf 'module offlineinitializer\n\ngo 1.24\n' > "$scratch/go.mod"
  run env GOPROXY=off GOSUMDB=off GOWORK=off go test -C "$scratch" -count=1 -v .
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

patch_offline_copy() {
  local scratch="$1"
  mkdir -p "$scratch"
  cp -R "$REPO_ROOT/vendor/src/anylinuxfs/init-rootfs/." "$scratch/"
  cp "$REPO_ROOT/build/alpine-packages.lock" "$scratch/default-alpine-packages.txt"
  REPO_ROOT="$REPO_ROOT" SCRATCH="$scratch" bash -c '
    set -euo pipefail
    source "$REPO_ROOT/build/lib/lock.sh"
    source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
    source "$REPO_ROOT/build/lib/patch-runtime-alpine.sh"
    source "$REPO_ROOT/build/lib/patch-offline-runtime.sh"
    runtime_alpine_load
    patch_init_rootfs_runtime_alpine "$SCRATCH" "$REPO_ROOT/build/alpine-apks.lock"
    patch_init_rootfs_offline_runtime "$SCRATCH" "$REPO_ROOT"
  '
}

@test "scratch initializer replaces all remote sources and embeds the trusted manifest" {
  local scratch="$BATS_TEST_TMPDIR/patched"
  run patch_offline_copy "$scratch"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
  ! grep -Eq 'http.Get|wget|docker.ParseReference|raw.githubusercontent.com|dl-cdn.alpinelinux.org' "$scratch/main.go"
  cmp "$REPO_ROOT/vendor/runtime/SHA256SUMS" "$scratch/offline-runtime.sha256"
  grep -Fq 'SourceCtx: sourceCtx' "$scratch/main.go"
  grep -Fq 'stageOfflineAPKs(cfg)' "$scratch/main.go"
}

@test "real patched initializer imports local OCI with networking denied and preserves cache on failure" {
  local scratch="$BATS_TEST_TMPDIR/integration" prefix="$BATS_TEST_TMPDIR/prefix"
  run patch_offline_copy "$scratch"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
  mkdir -p "$scratch/offlinetest" "$prefix/lib"
  cp -R "$REPO_ROOT/vendor/runtime" "$prefix/lib/ntfsmac-runtime"
  # Keep the real initialization/import/unpack functions and their dependencies;
  # replace only the cgo VM call and xattr stamping. Native VM setup is a separate gate.
  python3 - "$scratch" "$REPO_ROOT" <<'PYEOF'
from pathlib import Path
import sys
root,repo=map(Path,sys.argv[1:])
text=(root/'main.go').read_text()
text=text.replace('\t"anylinuxfs/init-rootfs/vmrunner"\n','')
text=text.replace('vmrunner.Run(', 'offlineTestVMRun(')
(root/'offlinetest/main.go').write_text(text)
for name in ('offline_runtime.go','offline_runtime_constants.go','offline-runtime.sha256','default-alpine-packages.txt'):
    (root/'offlinetest'/name).write_bytes((root/name).read_bytes())
(root/'offlinetest/stamp.go').write_text('package main\nimport "fmt"\nfunc stampOverrideStat(string) error { return nil }\nfunc offlineTestVMRun(string, string, string) error { return fmt.Errorf("VM must not be entered during verification") }\n')
(root/'offlinetest/offline_integration_test.go').write_bytes((repo/'build/runtime/offline_integration_test.go').read_bytes())
PYEOF
  run env GOPROXY=off GOSUMDB=off GOWORK=off CGO_ENABLED=0 go test -C "$scratch" -tags containers_image_openpgp -c -o "$scratch/offline.test" ./offlinetest
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
  run env GOPROXY=off GOSUMDB=off GOWORK=off CGO_ENABLED=0 go build -C "$scratch" -tags containers_image_openpgp -o "$scratch/offline-cli" ./offlinetest
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
  if [ "$(uname -s)" = Darwin ]; then
    run env NTFSMAC_OFFLINE_TEST_BINARY="$scratch/offline-cli" NTFSMAC_OFFLINE_TEST_PREFIX="$prefix" sandbox-exec -p '(version 1)(allow default)(deny network*)' "$scratch/offline.test" -test.v
  else
    skip "kernel network-denial integration requires macOS sandbox-exec"
  fi
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}
