#!/bin/bash
# cli/lib/run-with-progress.sh — shared background-job watchdog so no CLI subprocess call can
# leave the user staring at a blocked terminal with no feedback and no way out (backend-hang
# reports: degraded vmnet bridge / missing vendor binaries can wedge `anylinuxfs` indefinitely).
# No GNU coreutils `timeout` dependency (macOS ships none) — same manual background+kill
# pattern already used by build/init-rootfs.sh's own VM-boot bound, generalized for reuse.
set -u

# Print one process tree rooted at <pid>, parent first. anylinuxfs can create a new process group
# for its VM supervisor, so killing only the direct child is insufficient: vmnet-helper and the
# guest can otherwise survive a watchdog timeout even though the CLI has already returned.
# Parent/child ancestry remains authoritative across process-group changes and is available on
# both supported macOS and the Linux CI runners through pgrep -P.
run_with_progress_process_tree() {
  local root="$1" child children
  [[ "$root" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$root"
  children="$(/usr/bin/pgrep -P "$root" 2>/dev/null || true)"
  for child in $children; do
    run_with_progress_process_tree "$child"
  done
}

run_with_progress_terminate_tree() {
  local root="$1" tree pid
  tree="$(run_with_progress_process_tree "$root" 2>/dev/null || printf '%s\n' "$root")"

  # Signal the parent first so it cannot spawn another child after the snapshot, then every
  # recorded descendant (including descendants that entered their own process group/session).
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done <<< "$tree"
  sleep 1
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill -0 "$pid" 2>/dev/null || continue
    kill -KILL "$pid" 2>/dev/null || true
  done <<< "$tree"
}

# run_with_progress <timeout_secs> <heartbeat_secs> <label> <outfile|-> <cmd...>
#   <outfile>: capture <cmd>'s stdout there (caller reads it after a 0 return); set
#              RUN_WITH_PROGRESS_CAPTURE_STDERR=1 to capture stderr there as well. Pass "-" to
#              let <cmd> inherit this script's real stdout/stderr instead (used for anylinuxfs
#              mount/unmount, whose own live "macOS: ..." progress lines must stay visible,
#              not get buffered until the whole thing finishes).
#   Returns <cmd>'s real exit code on completion, or 124 (matching coreutils `timeout`'s
#   convention) after killing it once <timeout_secs> of wall time elapses with no exit —
#   printing exactly why, via <label>, before returning so the caller never has to guess.
run_with_progress() {
  local timeout_secs="$1" heartbeat_secs="$2" label="$3" outfile="$4"
  shift 4

  if [[ "$outfile" == "-" ]]; then
    "$@" &
  elif [[ "${RUN_WITH_PROGRESS_CAPTURE_STDERR:-0}" == "1" ]]; then
    "$@" > "$outfile" 2>&1 &
  else
    "$@" > "$outfile" 2>/dev/null &
  fi
  local pid=$!
  # `SECONDS` (bash builtin, auto-incrementing since shell start) instead of manually adding up
  # sleep durations — polls on a short 0.2s tick so a fast-exiting child (the common case) isn't
  # taxed a full heartbeat_secs of dead wait just to notice it's already done; heartbeat_secs
  # only paces how often the "still working" line prints, not how often we check.
  local start=$SECONDS next_heartbeat=$heartbeat_secs elapsed

  while kill -0 "$pid" 2>/dev/null; do
    sleep 0.2
    kill -0 "$pid" 2>/dev/null || break
    elapsed=$((SECONDS - start))
    if [[ $elapsed -ge $timeout_secs ]]; then
      run_with_progress_terminate_tree "$pid"
      wait "$pid" 2>/dev/null
      echo "$label: no response after ${timeout_secs}s — backend may be wedged (try 'ntfsmac diagnose')" >&2
      return 124
    fi
    if [[ $elapsed -ge $next_heartbeat ]]; then
      echo "$label: still working (${elapsed}s elapsed)..." >&2
      next_heartbeat=$((next_heartbeat + heartbeat_secs))
    fi
  done

  wait "$pid"
}
