#!/bin/bash
# Run the GUI test suite without letting a completed SwiftPM test helper wedge the build.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"

# shellcheck source=../cli/lib/run-with-progress.sh
source "$REPO_ROOT/cli/lib/run-with-progress.sh"

variant="${1:-}"
scratch_path="${2:-}"
timeout_secs="${NTFSMAC_SWIFT_TEST_TIMEOUT:-600}"
summary_grace_secs="${NTFSMAC_SWIFT_TEST_SUMMARY_GRACE:-3}"
heartbeat_secs="${NTFSMAC_SWIFT_TEST_HEARTBEAT:-15}"
swift_test_executable="${NTFSMAC_SWIFT_TEST_EXECUTABLE:-swift}"

case "$variant" in
  modern | legacy) ;;
  *)
    echo "usage: $0 <modern|legacy> <scratch-path>" >&2
    exit 2
    ;;
esac

if [[ -z "$scratch_path" ]]; then
  echo "usage: $0 <modern|legacy> <scratch-path>" >&2
  exit 2
fi

for value in "$timeout_secs" "$summary_grace_secs" "$heartbeat_secs"; do
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "Swift test watchdog values must be whole seconds." >&2
    exit 2
  fi
done

if [[ "$timeout_secs" -lt 1 || "$heartbeat_secs" -lt 1 ]]; then
  echo "Swift test timeout and heartbeat must be at least one second." >&2
  exit 2
fi

test_log="$(mktemp "${TMPDIR:-/tmp}/ntfsmac-swift-tests.XXXXXX")" || exit 1
status_file="${test_log}.status"
runner_pid=""

cleanup() {
  rm -f -- "$test_log" "$status_file"
}
trap cleanup EXIT

terminate_on_signal() {
  if [[ "$runner_pid" =~ ^[0-9]+$ ]]; then
    run_with_progress_terminate_tree "$runner_pid"
    wait "$runner_pid" 2>/dev/null || true
  fi
  exit 130
}
trap terminate_on_signal INT TERM

swift_test_args=(
  test
  --no-parallel
  --package-path "$REPO_ROOT"
  --scratch-path "$scratch_path"
)

# macOS 26.6.2 can wedge its CoreFoundation main executor when SwiftPM starts an
# ImageRenderer-based AppKit test. Keep compiling those tests, but skip only their named suite
# on the affected OS; CI and every other macOS release continue to execute them normally.
macos_version="${NTFSMAC_TEST_MACOS_VERSION:-$(sw_vers -productVersion 2>/dev/null || true)}"
if [[ "$macos_version" == "26.6.2" ]]; then
  echo "[WARN] macOS 26.6.2 AppKit runner issue: PopoverStateRenderTests are compiled but skipped for this local run." >&2
  swift_test_args+=(--skip PopoverStateRenderTests)
fi

# Keep tee inside one monitored subtree: the watchdog can then terminate SwiftPM, its
# swiftpm-testing-helper child, and tee without touching any unrelated build process.
(
  set -o pipefail
  NTFSMAC_HELPER_VARIANT="$variant" "$swift_test_executable" "${swift_test_args[@]}" 2>&1 | tee "$test_log"
  printf '%s\n' "${PIPESTATUS[0]}" > "$status_file"
) &
runner_pid=$!

start=$SECONDS
next_heartbeat=$heartbeat_secs
summary_seen_at=-1
success_pattern='Test run with [1-9][0-9]* tests .* passed after'

while kill -0 "$runner_pid" 2>/dev/null; do
  sleep 0.2
  kill -0 "$runner_pid" 2>/dev/null || break
  elapsed=$((SECONDS - start))

  if [[ "$summary_seen_at" -lt 0 ]] && grep -E -q "$success_pattern" "$test_log"; then
    summary_seen_at=$elapsed
  fi

  if [[ "$summary_seen_at" -ge 0 && $((elapsed - summary_seen_at)) -ge "$summary_grace_secs" ]]; then
    echo "Swift tests passed; closing an unresponsive SwiftPM test helper." >&2
    run_with_progress_terminate_tree "$runner_pid"
    wait "$runner_pid" 2>/dev/null || true
    exit 0
  fi

  if [[ "$elapsed" -ge "$timeout_secs" ]]; then
    run_with_progress_terminate_tree "$runner_pid"
    wait "$runner_pid" 2>/dev/null || true
    echo "Swift tests did not finish within ${timeout_secs}s; the GUI build was stopped." >&2
    exit 124
  fi

  if [[ "$elapsed" -ge "$next_heartbeat" ]]; then
    echo "Swift tests are still running (${elapsed}s elapsed)..." >&2
    next_heartbeat=$((next_heartbeat + heartbeat_secs))
  fi
done

wait "$runner_pid" 2>/dev/null || true
test_status="$(cat "$status_file" 2>/dev/null || printf '1')"
if [[ "$test_status" -ne 0 ]]; then
  exit "$test_status"
fi

if ! grep -E -q "$success_pattern" "$test_log"; then
  echo "Swift returned success without a completed non-empty test summary; refusing to package the GUI." >&2
  exit 1
fi

exit 0
