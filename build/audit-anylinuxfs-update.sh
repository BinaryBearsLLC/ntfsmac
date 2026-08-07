#!/bin/bash
# Read-only preflight for a proposed anylinuxfs pin update.
#
# This does not check out the candidate, edit the submodule, or update sources.lock. It resolves
# an already-fetched commit, summarizes the exact delta from the locked pin, and applies ntfsmac's
# source transformations only to a disposable archive under TMPDIR. Passing this preflight means
# "ready for human review and full gates", never "approved to merge".
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
SOURCE_DIR="${NTFSMAC_ANYLINUXFS_SOURCE:-$REPO_ROOT/vendor/src/anylinuxfs}"
EXPECTED_REMOTE="https://github.com/nohajc/anylinuxfs.git"

usage() {
  cat <<'EOF'
Usage: build/audit-anylinuxfs-update.sh <candidate-tag-or-commit>

The candidate object must already exist in vendor/src/anylinuxfs. Fetch it explicitly first:
  git -C vendor/src/anylinuxfs fetch --prune origin

This command is read-only with respect to the repository and always leaves the pin unchanged.
EOF
}

fail() {
  echo "audit-anylinuxfs-update: HARD-STOP — $*" >&2
  exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
[[ $# -eq 1 ]] || { usage >&2; exit 1; }
candidate_ref="$1"

[[ -d "$SOURCE_DIR/.git" || -f "$SOURCE_DIR/.git" ]] || fail "source checkout not found at $SOURCE_DIR"

# Paths are anchored from the runtime repository root and cannot be resolved by static ShellCheck.
# shellcheck disable=SC1091
source "$REPO_ROOT/build/lib/lock.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/build/lib/patch-runtime-alpine.sh"

current_pin=$(lock_get ANYLINUXFS_COMMIT) || exit 1
locked_version=$(lock_get ANYLINUXFS_VERSION) || exit 1
checked_out=$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null) || fail "cannot resolve checked-out submodule commit"
[[ "$checked_out" == "$current_pin" ]] || fail "checked-out submodule does not match ANYLINUXFS_COMMIT"

source_status_before=$(git -C "$SOURCE_DIR" status --porcelain)
[[ -z "$source_status_before" ]] || fail "submodule worktree is dirty; audit a clean pinned checkout"

remote_url=$(git -C "$SOURCE_DIR" remote get-url origin 2>/dev/null) || fail "origin remote is missing"
[[ "$remote_url" == "$EXPECTED_REMOTE" ]] || fail "origin is not the audited nohajc/anylinuxfs repository"

candidate_commit=$(git -C "$SOURCE_DIR" rev-parse --verify "${candidate_ref}^{commit}" 2>/dev/null) \
  || fail "candidate '$candidate_ref' is unavailable; fetch origin explicitly and retry"
git -C "$SOURCE_DIR" merge-base --is-ancestor "$current_pin" "$candidate_commit" \
  || fail "candidate is not a descendant of the locked pin"

manifest_at() {
  local commit="$1" path="$2"
  git -C "$SOURCE_DIR" show "$commit:$path" 2>/dev/null \
    || fail "candidate is missing required manifest $path"
}

package_version_at() {
  local commit="$1" path="$2"
  manifest_at "$commit" "$path" | awk -F '"' '/^version = "/ { print $2; exit }'
}

current_version=$(package_version_at "$current_pin" anylinuxfs/Cargo.toml)
candidate_version=$(package_version_at "$candidate_commit" anylinuxfs/Cargo.toml)
candidate_vmproxy_version=$(package_version_at "$candidate_commit" vmproxy/Cargo.toml)
[[ -n "$current_version" && -n "$candidate_version" && -n "$candidate_vmproxy_version" ]] \
  || fail "could not resolve package versions from candidate manifests"
[[ "$current_version" == "$locked_version" ]] \
  || fail "locked ANYLINUXFS_VERSION does not match the pinned source manifest"

commit_count=$(git -C "$SOURCE_DIR" rev-list --count "$current_pin..$candidate_commit")
commit_log=$(git -C "$SOURCE_DIR" log --reverse --format='%H %s' "$current_pin..$candidate_commit")
changed_files=$(git -C "$SOURCE_DIR" diff --name-only "$current_pin..$candidate_commit")
changed_file_count=$(printf '%s\n' "$changed_files" | awk 'NF { count++ } END { print count + 0 }')
candidate_tags=$(git -C "$SOURCE_DIR" tag --points-at "$candidate_commit" | paste -sd, -)
[[ -n "$candidate_tags" ]] || candidate_tags="none"

dependency_files_changed=false
source_paths_changed=false
package_manifest_changed=false
download_contract_changed=false
if grep -Eq '(^|/)(Cargo\.(toml|lock)|go\.(mod|sum))$' <<< "$changed_files"; then
  dependency_files_changed=true
fi
if grep -Eq '^(anylinuxfs/src/|common-utils/src/|vmproxy/src/|vmrunner-sys/src/|init-rootfs/.*\.go$|.*\.sh$|etc/|share/)' <<< "$changed_files"; then
  source_paths_changed=true
fi
if grep -Fxq 'init-rootfs/default-alpine-packages.txt' <<< "$changed_files"; then
  package_manifest_changed=true
fi
if grep -Fxq 'download-dependencies.sh' <<< "$changed_files"; then
  download_contract_changed=true
fi

# Exercise the exact ntfsmac transformations against the candidate without checking it out.
audit_tmp=$(mktemp -d "${TMPDIR:-/tmp}/ntfsmac-anylinuxfs-audit.XXXXXX")
trap 'rm -rf "$audit_tmp"' EXIT
git -C "$SOURCE_DIR" archive "$candidate_commit" | tar -x -C "$audit_tmp"
runtime_alpine_load || fail "could not derive the locked Alpine runtime contract"
patch_anylinuxfs_runtime_alpine "$audit_tmp" >/dev/null \
  || fail "runtime Alpine patch no longer applies to the candidate"
patch_init_rootfs_runtime_alpine "$audit_tmp/init-rootfs" >/dev/null \
  || fail "init-rootfs runtime patch no longer applies to the candidate"

source_status_after=$(git -C "$SOURCE_DIR" status --porcelain)
[[ "$source_status_after" == "$source_status_before" ]] || fail "audit unexpectedly modified the submodule"
[[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" == "$checked_out" ]] || fail "audit unexpectedly moved the submodule HEAD"

printf 'current_pin=%s\n' "$current_pin"
printf 'current_version=%s\n' "$current_version"
printf 'candidate_commit=%s\n' "$candidate_commit"
printf 'candidate_version=%s\n' "$candidate_version"
printf 'candidate_vmproxy_version=%s\n' "$candidate_vmproxy_version"
printf 'candidate_tags=%s\n' "$candidate_tags"
printf 'commit_count=%s\n' "$commit_count"
printf 'changed_file_count=%s\n' "$changed_file_count"
printf 'dependency_files_changed=%s\n' "$dependency_files_changed"
printf 'source_paths_changed=%s\n' "$source_paths_changed"
printf 'package_manifest_changed=%s\n' "$package_manifest_changed"
printf 'download_contract_changed=%s\n' "$download_contract_changed"
printf 'local_patch_compatibility=pass\n'
printf 'repository_mutated=false\n'
while IFS= read -r commit_line; do
  [[ -n "$commit_line" ]] && printf 'commit=%s\n' "$commit_line"
done <<< "$commit_log"
while IFS= read -r changed_file; do
  [[ -n "$changed_file" ]] && printf 'changed_file=%s\n' "$changed_file"
done <<< "$changed_files"
printf 'release_notes_review=required\n'
printf 'dependency_review=required\n'
printf 'full_build_and_hardware_gates=required\n'
printf 'decision=pending_manual_review\n'
