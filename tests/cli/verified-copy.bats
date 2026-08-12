#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COPY_SCRIPT="$REPO_ROOT/cli/commands/copy.sh"
  VERIFY_SCRIPT="$REPO_ROOT/cli/commands/verify.sh"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

@test "verified file copy publishes only after a reread SHA-256 match" {
  printf 'stable source bytes\n' > "$FIXTURE_DIR/source.bin"

  run "$COPY_SCRIPT" --verify "$FIXTURE_DIR/source.bin" "$FIXTURE_DIR/destination.bin"

  [ "$status" -eq 0 ]
  [ -f "$FIXTURE_DIR/source.bin" ]
  run cmp "$FIXTURE_DIR/source.bin" "$FIXTURE_DIR/destination.bin"
  [ "$status" -eq 0 ]
  [[ "$output" == "" ]]
  run find "$FIXTURE_DIR" -maxdepth 1 -name '*.ntfsmac-partial.*'
  [ "$output" = "" ]
}

@test "directory manifest handles nested Unicode spaces newlines and symlinks without following them" {
  mkdir -p "$FIXTURE_DIR/source tree/nested"
  printf 'alpha\n' > "$FIXTURE_DIR/source tree/nested/film one.mkv"
  printf 'unicode\n' > "$FIXTURE_DIR/source tree/caffè.txt"
  local newline_name=$'line\nbreak.txt'
  printf 'newline\n' > "$FIXTURE_DIR/source tree/$newline_name"
  ln -s 'nested/film one.mkv' "$FIXTURE_DIR/source tree/film-link"

  run "$COPY_SCRIPT" --verify "$FIXTURE_DIR/source tree" "$FIXTURE_DIR/copied tree"
  [ "$status" -eq 0 ]
  [ -L "$FIXTURE_DIR/copied tree/film-link" ]
  [ "$(readlink "$FIXTURE_DIR/copied tree/film-link")" = 'nested/film one.mkv' ]

  run "$VERIFY_SCRIPT" "$FIXTURE_DIR/source tree" "$FIXTURE_DIR/copied tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"manifest match"* ]]

  printf 'changed\n' >> "$FIXTURE_DIR/copied tree/nested/film one.mkv"
  run "$VERIFY_SCRIPT" "$FIXTURE_DIR/source tree" "$FIXTURE_DIR/copied tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"differs"* ]]
}

@test "directory copy tolerates destination-only AppleDouble metadata without ignoring real sidecars" {
  mkdir -p "$FIXTURE_DIR/source tree"
  printf 'payload\n' > "$FIXTURE_DIR/source tree/file.txt"
  printf 'real sidecar bytes\n' > "$FIXTURE_DIR/source tree/._intentional"

  local copyfile_aware_cp="$FIXTURE_DIR/copyfile-aware-cp"
  cat > "$copyfile_aware_cp" <<'SCRIPT'
#!/bin/bash
last=""
metadata_disabled=false
for item in "$@"; do
  last="$item"
  [[ "$item" == -*X* ]] && metadata_disabled=true
done
/bin/cp "$@" || exit
# NFS can synthesize this sidecar for com.apple.provenance even when cp receives -X.
printf '\000\005\026\007Mac OS X metadata\n' > "$last/._file.txt"
if [[ "$metadata_disabled" != "true" ]]; then exit 97; fi
SCRIPT
  chmod +x "$copyfile_aware_cp"

  NTFSMAC_CP_BIN="$copyfile_aware_cp" run \
    "$COPY_SCRIPT" --verify "$FIXTURE_DIR/source tree" "$FIXTURE_DIR/copied tree"

  [ "$status" -eq 0 ]
  [ -f "$FIXTURE_DIR/copied tree/._intentional" ]
  [ -f "$FIXTURE_DIR/copied tree/._file.txt" ]
  [[ "$output" == *"manifest match"* ]]

  printf 'not AppleDouble\n' > "$FIXTURE_DIR/copied tree/._unexpected"
  run "$VERIFY_SCRIPT" "$FIXTURE_DIR/source tree" "$FIXTURE_DIR/copied tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"differs"* ]]
}

@test "existing destination is never overwritten" {
  printf 'source\n' > "$FIXTURE_DIR/source"
  printf 'keep me\n' > "$FIXTURE_DIR/destination"

  run "$COPY_SCRIPT" --verify "$FIXTURE_DIR/source" "$FIXTURE_DIR/destination"

  [ "$status" -ne 0 ]
  [ "$(cat "$FIXTURE_DIR/destination")" = "keep me" ]
  [[ "$output" == *"refusing to overwrite"* ]]
}

@test "a corrupted temporary payload fails verification and remains recoverable" {
  printf 'source\n' > "$FIXTURE_DIR/source"
  local corrupt_cp="$FIXTURE_DIR/corrupt-cp"
  printf '#!/bin/bash\nlast=""\nfor item in "$@"; do last="$item"; done\n/bin/cp "$@" || exit\nprintf corrupt >> "$last"\n' > "$corrupt_cp"
  chmod +x "$corrupt_cp"

  NTFSMAC_CP_BIN="$corrupt_cp" run "$COPY_SCRIPT" --verify "$FIXTURE_DIR/source" "$FIXTURE_DIR/destination"

  [ "$status" -ne 0 ]
  [ -f "$FIXTURE_DIR/source" ]
  [ ! -e "$FIXTURE_DIR/destination" ]
  [[ "$output" == *"recoverable partial copy retained"* ]]
  run find "$FIXTURE_DIR" -maxdepth 1 -type d -name '.destination.ntfsmac-partial.*'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output/payload" ]
}

@test "destination inside a source tree is refused before creating partial state" {
  mkdir -p "$FIXTURE_DIR/source/subdir"
  printf 'data\n' > "$FIXTURE_DIR/source/file"

  run "$COPY_SCRIPT" --verify "$FIXTURE_DIR/source" "$FIXTURE_DIR/source/subdir/copy"

  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be inside"* ]]
  run find "$FIXTURE_DIR/source" -name '*.ntfsmac-partial.*'
  [ "$output" = "" ]
}

@test "root symlink is compared by target text and never dereferenced" {
  printf 'target\n' > "$FIXTURE_DIR/target"
  ln -s target "$FIXTURE_DIR/source-link"
  ln -s target "$FIXTURE_DIR/same-link"
  ln -s elsewhere "$FIXTURE_DIR/different-link"

  run "$VERIFY_SCRIPT" "$FIXTURE_DIR/source-link" "$FIXTURE_DIR/same-link"
  [ "$status" -eq 0 ]
  run "$VERIFY_SCRIPT" "$FIXTURE_DIR/source-link" "$FIXTURE_DIR/different-link"
  [ "$status" -ne 0 ]
}

@test "invalid command shapes show the strict contract" {
  run "$COPY_SCRIPT" "$FIXTURE_DIR/a" "$FIXTURE_DIR/b"
  [ "$status" -eq 2 ]
  run "$VERIFY_SCRIPT" "$FIXTURE_DIR/a"
  [ "$status" -eq 2 ]
  run "$COPY_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not guarantee against later media"* ]]
}
