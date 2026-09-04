#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GO_MOD_CACHE="$(go env GOMODCACHE)"
  GO_BUILD_CACHE="$(go env GOCACHE)"
  GO_PATH="$(go env GOPATH)"
  POISON_HOME="$BATS_TEST_TMPDIR/poison-home"
}

teardown() {
  if [ -d "${POISON_HOME:-}" ]; then
    chmod -R u+rwX "$POISON_HOME" 2>/dev/null || true
  fi
}

patch_runtime_copy() {
  local scratch="$1"
  mkdir -p "$scratch"
  cp -R "$REPO_ROOT/vendor/src/anylinuxfs/init-rootfs/." "$scratch/"

  REPO_ROOT="$REPO_ROOT" SCRATCH="$scratch" bash -c '
    set -euo pipefail
    source "$REPO_ROOT/build/lib/lock.sh"
    source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
    source "$REPO_ROOT/build/lib/patch-runtime-alpine.sh"
    runtime_alpine_load
    patch_init_rootfs_runtime_alpine "$SCRATCH"
  '
}

@test "init-rootfs isolates every user OCI registry and authentication input" {
  local scratch
  scratch="$BATS_TEST_TMPDIR/static-init-rootfs"

  run patch_runtime_copy "$scratch"

  [ "$status" -eq 0 ]
  [[ "$output" == *"isolated OCI configuration"* ]]
  grep -Fq 'RegistriesDirPath:' "$scratch/main.go"
  grep -Fq 'SystemRegistriesConfPath:' "$scratch/main.go"
  grep -Fq 'SystemRegistriesConfDirPath:' "$scratch/main.go"
  grep -Fq 'UserShortNameAliasConfPath:' "$scratch/main.go"
  grep -Fq 'DockerAuthConfig:' "$scratch/main.go"
  [ "$(grep -c 'SourceCtx: sourceCtx' "$scratch/main.go")" -eq 1 ]
}

@test "patched resolver ignores unreadable registries.conf and unrelated container settings" {
  local scratch poison_home
  scratch="$BATS_TEST_TMPDIR/functional-init-rootfs"
  poison_home="$POISON_HOME"
  mkdir -p "$poison_home/.config/containers/registries.conf.d" \
    "$poison_home/.config/containers/registries.d" \
    "$poison_home/.docker"
  printf '%s\n' 'this is deliberately invalid' > "$poison_home/.config/containers/registries.conf"
  printf '%s\n' 'also invalid' > "$poison_home/.config/containers/short-name-aliases.conf"
  printf '%s\n' '{not-json' > "$poison_home/.docker/config.json"
  chmod 000 "$poison_home/.config/containers/registries.conf" \
    "$poison_home/.config/containers/registries.conf.d" \
    "$poison_home/.config/containers/registries.d" \
    "$poison_home/.config/containers/short-name-aliases.conf" \
    "$poison_home/.docker/config.json"

  run patch_runtime_copy "$scratch"
  [ "$status" -eq 0 ]

  mkdir -p "$scratch/runtimeconfig"
  python3 - "$scratch/main.go" "$scratch/runtimeconfig/context.go" <<'PYEOF'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("func isolatedRegistryContext")
end = source.index("\nfunc downloadImage", start)
function = source[start:end]
Path(sys.argv[2]).write_text('''package runtimeconfig

import (
\t"fmt"
\t"os"
\t"path/filepath"

\t"go.podman.io/image/v5/types"
)

''' + function + "\n")
PYEOF

  cat > "$scratch/runtimeconfig/runtime_config_test.go" <<'GOEOF'
package runtimeconfig

import (
	"os"
	"path/filepath"
	"testing"

	dockerconfig "go.podman.io/image/v5/pkg/docker/config"
	"go.podman.io/image/v5/pkg/sysregistriesv2"
)

func TestRuntimeRegistryContextIsSelfContained(t *testing.T) {
	base := t.TempDir()
	ctx, err := isolatedRegistryContext(base)
	if err != nil {
		t.Fatal(err)
	}
	if ctx.DockerAuthConfig == nil {
		t.Fatal("public runtime pull must not inherit user Docker credentials")
	}

	for _, path := range []string{
		ctx.RegistriesDirPath,
		ctx.SystemRegistriesConfPath,
		ctx.SystemRegistriesConfDirPath,
		ctx.UserShortNameAliasConfPath,
	} {
		rel, err := filepath.Rel(base, path)
		if err != nil || rel == ".." || filepath.IsAbs(rel) {
			t.Fatalf("isolated path escaped runtime cache: %q", path)
		}
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("isolated path is unavailable: %q: %v", path, err)
		}
	}

	registries, err := sysregistriesv2.GetRegistries(ctx)
	if err != nil {
		t.Fatalf("isolated registries.conf was not used: %v", err)
	}
	if len(registries) != 0 {
		t.Fatalf("unexpected inherited registry configuration: %#v", registries)
	}

	credentials, err := dockerconfig.GetCredentials(ctx, "docker.io")
	if err != nil {
		t.Fatalf("user Docker configuration was consulted: %v", err)
	}
	if credentials.Username != "" || credentials.Password != "" || credentials.IdentityToken != "" {
		t.Fatalf("unexpected inherited registry credentials: %#v", credentials)
	}
}
GOEOF

  run env \
    HOME="$poison_home" \
    XDG_CONFIG_HOME="$poison_home/.config" \
    CONTAINERS_REGISTRIES_CONF="$poison_home/.config/containers/registries.conf" \
    REGISTRY_AUTH_FILE="$poison_home/.docker/config.json" \
    DOCKER_CONFIG="$poison_home/.docker" \
    GOMODCACHE="$GO_MOD_CACHE" \
    GOCACHE="$GO_BUILD_CACHE" \
    GOPATH="$GO_PATH" \
    GOWORK=off \
    bash -c 'cd "$1" && exec go test ./runtimeconfig -run "^TestRuntimeRegistryContextIsSelfContained$" -count=1' _ "$scratch"

  local go_status="$status" go_output="$output"
  chmod 700 "$poison_home/.config/containers/registries.conf.d" \
    "$poison_home/.config/containers/registries.d"
  chmod 600 "$poison_home/.config/containers/registries.conf" \
    "$poison_home/.config/containers/short-name-aliases.conf" \
    "$poison_home/.docker/config.json"

  if [ "$go_status" -ne 0 ]; then
    printf '%s\n' "$go_output" >&2
  fi
  [ "$go_status" -eq 0 ]
  [[ "$go_output" == *"ok"* ]]
}
