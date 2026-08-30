#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  BASE_LOCK="$REPO_ROOT/build/alpine-base-packages.lock"
  PACKAGE_LOCK="$REPO_ROOT/build/alpine-packages.lock"
  APK_LOCK="$REPO_ROOT/build/alpine-apks.lock"
  TRIMMED="$REPO_ROOT/build/alpine-packages.trimmed.txt"
  # shellcheck source=../../build/lib/lock.sh
  source "$REPO_ROOT/build/lib/lock.sh"
}

@test "base and add-on package locks are exact sorted unique manifests" {
  [ "$(wc -l < "$BASE_LOCK" | tr -d ' ')" -eq 16 ]
  [ "$(wc -l < "$PACKAGE_LOCK" | tr -d ' ')" -eq 54 ]
  [ "$(wc -l < "$APK_LOCK" | tr -d ' ')" -eq 54 ]
  LC_ALL=C sort -cu "$BASE_LOCK"
  LC_ALL=C sort -cu "$PACKAGE_LOCK"
  run grep -Ev '^[a-z0-9][a-z0-9+_.-]*=[A-Za-z0-9][A-Za-z0-9+_.:~-]*-r[0-9]+$' "$BASE_LOCK" "$PACKAGE_LOCK"
  [ "$status" -ne 0 ]
}

@test "APK artifact lock matches the add-on manifest exactly" {
  local constraints
  constraints="$BATS_TEST_TMPDIR/apk-constraints"
  awk '{print $1}' "$APK_LOCK" > "$constraints"
  cmp "$PACKAGE_LOCK" "$constraints"
  run awk 'NF != 3 || $2 !~ /^(v[0-9]+\.[0-9]+|edge)\/(main|community)$/ || $3 !~ /^[0-9a-f]+$/ || length($3) != 64 { exit 1 }' "$APK_LOCK"
  [ "$status" -eq 0 ]
}

@test "package lock validation rejects shell metacharacters" {
  local fixture expected
  fixture="$BATS_TEST_TMPDIR/unsafe-packages.lock"
  printf 'bash=5.3.3-r1;touch-danger\n' > "$fixture"
  expected="$(shasum -a 256 "$fixture" | awk '{print $1}')"

  run bash -c 'source build/init-rootfs.sh; verify_package_lock "$1" "$2" test' _ "$fixture" "$expected"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid or non-exact package constraint"* ]]
}

@test "sources.lock hashes match both package manifests" {
  local expected actual
  expected="$(lock_get ALPINE_BASE_PACKAGES_SHA256)"
  actual="$(shasum -a 256 "$BASE_LOCK" | awk '{print $1}')"
  [ "$actual" = "$expected" ]

  expected="$(lock_get ALPINE_PACKAGES_SHA256)"
  actual="$(shasum -a 256 "$PACKAGE_LOCK" | awk '{print $1}')"
  [ "$actual" = "$expected" ]

  expected="$(lock_get ALPINE_APKS_SHA256)"
  actual="$(shasum -a 256 "$APK_LOCK" | awk '{print $1}')"
  [ "$actual" = "$expected" ]
}

@test "every reviewed direct package is locked and every audited cut stays absent" {
  local package
  while IFS= read -r package; do
    run grep -E "^${package}=[^[:space:]]+$" "$PACKAGE_LOCK"
    [ "$status" -eq 0 ]
  done < "$TRIMMED"

  for package in btrfs-progs mdadm zfs; do
    run grep -E "^${package}=" "$PACKAGE_LOCK"
    [ "$status" -ne 0 ]
  done
}

@test "OCI base and add-on closure do not overlap" {
  local base_names addon_names
  base_names="$(mktemp)"
  addon_names="$(mktemp)"
  sed 's/=.*//' "$BASE_LOCK" | LC_ALL=C sort > "$base_names"
  sed 's/=.*//' "$PACKAGE_LOCK" | LC_ALL=C sort > "$addon_names"
  run comm -12 "$base_names" "$addon_names"
  rm -f "$base_names" "$addon_names"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the current lock records one coherent ntfs-3g package family" {
  run grep -E '^ntfs-3g(-libs|-progs)?=2026\.7\.7-r0$' "$PACKAGE_LOCK"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "only the ntfs-3g security family may use the edge channel" {
  run awk '$2 ~ /^edge\// && $1 !~ /^ntfs-3g(-libs|-progs)?=2026\.7\.7-r0$/ { print; bad=1 } END { exit bad }' "$APK_LOCK"
  [ "$status" -eq 0 ]
  [ "$(awk '$2 == "edge/main" { count++ } END { print count + 0 }' "$APK_LOCK")" -eq 3 ]
}

@test "runtime validation rejects edge for a non-ntfs package" {
  local fixture expected
  fixture="$BATS_TEST_TMPDIR/unapproved-edge.lock"
  sed 's/^bash=5\.3\.3-r1 v3\.23\/main /bash=5.3.3-r1 edge\/main /' "$APK_LOCK" > "$fixture"
  expected="$(shasum -a 256 "$fixture" | awk '{print $1}')"

  run env FIXTURE="$fixture" EXPECTED="$expected" bash -c '
    source build/init-rootfs.sh
    runtime_alpine_load
    APK_LOCK="$FIXTURE"
    ALPINE_APKS_SHA256="$EXPECTED"
    verify_apk_lock
  '

  [ "$status" -ne 0 ]
  [[ "$output" == *"edge is approved only for the ntfs-3g"* ]]
}
