#!/bin/bash
# Deterministic byte-integrity primitives for `ntfsmac copy --verify` and `ntfsmac verify`.
# Metadata outside entry type, regular-file size/content, and symlink target text is deliberately
# out of contract; see README and the command help.

VERIFIED_COPY_CP_BIN="${NTFSMAC_CP_BIN:-/bin/cp}"
VERIFIED_COPY_MV_BIN="${NTFSMAC_MV_BIN:-/bin/mv}"
VERIFIED_COPY_SYNC_BIN="${NTFSMAC_SYNC_BIN:-$(command -v sync 2>/dev/null)}"
VERIFIED_COPY_SHASUM_BIN="${NTFSMAC_SHASUM_BIN:-/usr/bin/shasum}"

verified_copy_absolute_path() {
  local input="$1" parent base
  while [[ "$input" != "/" && "$input" == */ ]]; do input="${input%/}"; done
  parent="$(dirname "$input")"
  base="$(basename "$input")"
  [[ -d "$parent" ]] || return 1
  parent="$(cd -- "$parent" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "${parent%/}" "$base"
}

verified_copy_hex() {
  LC_ALL=C printf '%s' "$1" | /usr/bin/od -An -tx1 | /usr/bin/tr -d ' \n'
}

verified_copy_hash_stream() {
  "$VERIFIED_COPY_SHASUM_BIN" -a 256 | /usr/bin/awk '{print $1}'
}

verified_copy_hash_file() {
  "$VERIFIED_COPY_SHASUM_BIN" -a 256 "$1" | /usr/bin/awk '{print $1}'
}

verified_copy_manifest_entry() {
  local root="$1" path="$2" rel type size hash target
  if [[ "$path" == "$root" ]]; then rel="."; else rel="${path#"$root"/}"; fi

  if [[ -L "$path" ]]; then
    type="L"
    target="$(/usr/bin/readlink "$path")" || return 1
    size="$(LC_ALL=C printf '%s' "$target" | /usr/bin/wc -c | /usr/bin/tr -d ' ')"
    hash="$(LC_ALL=C printf '%s' "$target" | verified_copy_hash_stream)" || return 1
  elif [[ -f "$path" ]]; then
    type="F"
    size="$(/usr/bin/stat -f '%z' "$path")" || return 1
    hash="$(verified_copy_hash_file "$path")" || return 1
  elif [[ -d "$path" ]]; then
    type="D"
    size="0"
    hash="-"
  else
    echo "verified-copy: unsupported entry type encountered" >&2
    return 1
  fi

  printf '%s\t%s\t%s\t%s\n' "$(verified_copy_hex "$rel")" "$type" "$size" "$hash"
}

# macOS writes excluded xattrs (notably com.apple.provenance) as AppleDouble `._*` files when the
# destination filesystem cannot store them natively.  Ignore only a destination-only sidecar with
# the AppleDouble magic, an existing paired entry, and no same-path entry in the source.  A real
# source file named `._something` remains part of the manifest and is still verified byte-for-byte.
verified_copy_is_synthetic_appledouble() {
  local destination_root="$1" path="$2" source_root="$3" rel base directory paired magic
  [[ -n "$source_root" && -f "$path" && ! -L "$path" ]] || return 1
  rel="${path#"$destination_root"/}"
  base="${rel##*/}"
  [[ "$base" == ._* ]] || return 1
  [[ ! -e "$source_root/$rel" && ! -L "$source_root/$rel" ]] || return 1

  if [[ "$rel" == */* ]]; then
    directory="${rel%/*}/"
  else
    directory=""
  fi
  paired="$destination_root/${directory}${base#._}"
  [[ -e "$paired" || -L "$paired" ]] || return 1

  magic="$(/usr/bin/od -An -tx1 -N4 "$path" 2>/dev/null | /usr/bin/tr -d ' \n')" || return 1
  [[ "$magic" == "00051607" ]]
}

# Manifest records are sorted by the hex-encoded relative path. This remains deterministic for
# spaces, tabs, newlines, Unicode, and leading dashes without making filenames executable shell
# input. Regular files hash bytes in a stream; symlinks hash their link text and are never followed.
verified_copy_manifest() {
  local root="$1" output="$2" source_reference="${3:-}" entries unsorted path
  entries="${output}.entries"
  unsorted="${output}.unsorted"
  : > "$unsorted" || return 1
  verified_copy_manifest_entry "$root" "$root" >> "$unsorted" || return 1

  if [[ -d "$root" && ! -L "$root" ]]; then
    /usr/bin/find "$root" -mindepth 1 -print0 > "$entries" || return 1
    while IFS= read -r -d '' path; do
      if verified_copy_is_synthetic_appledouble "$root" "$path" "$source_reference"; then
        continue
      fi
      verified_copy_manifest_entry "$root" "$path" >> "$unsorted" || return 1
    done < "$entries"
  fi

  LC_ALL=C /usr/bin/sort "$unsorted" > "$output" || return 1
  rm -f "$entries" "$unsorted"
}

verified_copy_supported_root() {
  [[ -L "$1" || -f "$1" || -d "$1" ]]
}

verified_copy_compare() {
  local first="$1" second="$2" scratch="$3"
  verified_copy_supported_root "$first" || {
    echo "verified-copy: source is not a regular file, directory, or symlink" >&2
    return 1
  }
  verified_copy_supported_root "$second" || {
    echo "verified-copy: destination is not a regular file, directory, or symlink" >&2
    return 1
  }
  verified_copy_manifest "$first" "$scratch/source.manifest" || return 1
  verified_copy_manifest "$second" "$scratch/destination.manifest" "$first" || return 1
  /usr/bin/cmp -s "$scratch/source.manifest" "$scratch/destination.manifest"
}

verified_copy_verify_main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
usage: verify.sh <source> <destination>

Compare existing files, directory trees, or symlinks using a deterministic manifest of entry
type, regular-file size and SHA-256, or symlink target text. Symlinks are never followed.
Permissions, ownership, ACLs, extended attributes, resource forks, timestamps, hard-link
relationships, and sparse allocation are outside this byte-integrity comparison.
HELP
    return 0
  fi
  [[ $# -eq 2 ]] || { echo "verify: expected <source> <destination>" >&2; return 2; }

  local source destination scratch result=0
  source="$(verified_copy_absolute_path "$1")" || { echo "verify: source parent does not exist" >&2; return 1; }
  destination="$(verified_copy_absolute_path "$2")" || { echo "verify: destination parent does not exist" >&2; return 1; }
  verified_copy_supported_root "$source" || { echo "verify: source does not exist or has an unsupported type" >&2; return 1; }
  verified_copy_supported_root "$destination" || { echo "verify: destination does not exist or has an unsupported type" >&2; return 1; }

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/ntfsmac-verify.XXXXXX")" || return 1
  verified_copy_compare "$source" "$destination" "$scratch" || result=$?
  rm -rf "$scratch"
  if [[ "$result" -eq 0 ]]; then
    echo "verify: SHA-256 manifest match"
    return 0
  fi
  echo "verify: FAILED — entry type, size, symlink target, or SHA-256 differs" >&2
  return 1
}

verified_copy_copy_main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
usage: copy.sh --verify <source> <destination>

Copy to a recoverable temporary location beside the final destination, flush, reread and compare
a deterministic SHA-256 manifest, then rename into place. The final destination must not exist;
there is no implicit overwrite. On failure the source is never removed and the partial-copy
directory is retained and printed. Symlinks are copied as symlinks and never followed.

The comparison validates bytes read at that time. It does not guarantee against later media
failure or preserve/verify every macOS metadata field.
HELP
    return 0
  fi
  [[ "${1:-}" == "--verify" && $# -eq 3 ]] || {
    echo "copy: expected --verify <source> <destination>" >&2
    return 2
  }

  local source destination parent name recovery payload result=0
  source="$(verified_copy_absolute_path "$2")" || { echo "copy: source parent does not exist" >&2; return 1; }
  destination="$(verified_copy_absolute_path "$3")" || { echo "copy: destination parent does not exist" >&2; return 1; }
  verified_copy_supported_root "$source" || { echo "copy: source does not exist or has an unsupported type" >&2; return 1; }
  [[ ! -e "$destination" && ! -L "$destination" ]] || { echo "copy: destination already exists; refusing to overwrite" >&2; return 1; }
  [[ "$source" != "$destination" ]] || { echo "copy: source and destination are the same" >&2; return 1; }

  parent="$(dirname "$destination")"
  name="$(basename "$destination")"
  [[ -d "$parent" && -w "$parent" && "$name" != "." && "$name" != ".." ]] || {
    echo "copy: destination directory is not writable" >&2
    return 1
  }
  if [[ -d "$source" && ! -L "$source" && ( "$parent" == "$source" || "$parent" == "$source"/* ) ]]; then
    echo "copy: destination cannot be inside the source directory" >&2
    return 1
  fi
  [[ -x "$VERIFIED_COPY_CP_BIN" && -x "$VERIFIED_COPY_MV_BIN" \
    && -x "$VERIFIED_COPY_SHASUM_BIN" && -n "$VERIFIED_COPY_SYNC_BIN" \
    && -x "$VERIFIED_COPY_SYNC_BIN" ]] || {
    echo "copy: required system copy, rename, sync, or SHA-256 tool is unavailable" >&2
    return 1
  }

  recovery="$(mktemp -d "$parent/.${name}.ntfsmac-partial.XXXXXX")" || return 1
  payload="$recovery/payload"
  trap 'echo "copy: interrupted — recoverable partial copy retained at: $recovery" >&2; exit 130' INT TERM HUP

  # The integrity contract deliberately excludes xattrs and resource forks.  On filesystems that
  # cannot store them natively (including the NTFS volume exposed through our NFS mount), macOS
  # otherwise materializes that metadata as `._*` AppleDouble files.  Those are new directory
  # entries, so they correctly make the byte manifest differ from the source.  Disable copyfile
  # metadata synthesis for this bounded copy instead of teaching the verifier to ignore real
  # source files that happen to begin with `._`.  `-X` is the macOS cp contract for this; the
  # environment variable is retained as a defensive copyfile hint for the same subprocess.
  if ! COPYFILE_DISABLE=1 "$VERIFIED_COPY_CP_BIN" -pRX "$source" "$payload"; then
    echo "copy: FAILED — recoverable partial copy retained at: $recovery" >&2
    trap - INT TERM HUP
    return 1
  fi
  "$VERIFIED_COPY_SYNC_BIN" || true

  verified_copy_compare "$source" "$payload" "$recovery" || result=$?
  if [[ "$result" -ne 0 ]]; then
    echo "copy: FAILED verification — recoverable partial copy retained at: $recovery" >&2
    trap - INT TERM HUP
    return 1
  fi

  rm -f "$recovery/source.manifest" "$recovery/destination.manifest"
  if ! "$VERIFIED_COPY_MV_BIN" "$payload" "$destination"; then
    echo "copy: FAILED final rename — recoverable partial copy retained at: $recovery" >&2
    trap - INT TERM HUP
    return 1
  fi
  rmdir "$recovery" 2>/dev/null || true
  trap - INT TERM HUP
  echo "copy: verified SHA-256 manifest match; destination published"
}
