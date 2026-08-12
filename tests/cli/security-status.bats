#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/cli/lib/security-status.sh"
  FIXTURE_DIR="$(mktemp -d)"
  export NTFSMAC_SECURITY_STATUS_FILE="$FIXTURE_DIR/security-status"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

write_valid_status() {
  printf '%s\n' \
    'schema=1' \
    'active_sessions=2' \
    'private_link=enforced' \
    'private_reason=PRIVATE_VMNET_SOFT' \
    'vpn_route=notRequired' \
    'vpn_route_reason=ROUTE_ALREADY_PRIVATE' \
    'pf_policy=enforced' \
    'pf_reason=PF_EVALUATED' \
    'overall=enforced' \
    'overall_reason=SECURITY_ENFORCED' > "$NTFSMAC_SECURITY_STATUS_FILE"
}

@test "loads only the fixed privacy-safe summary fields" {
  write_valid_status

  run bash -c "source '$SCRIPT'; security_summary_load; printf '%s|%s|%s|%s|%s\n' \"\$SECURITY_ACTIVE_SESSIONS\" \"\$SECURITY_PRIVATE_LINK\" \"\$SECURITY_VPN_ROUTE\" \"\$SECURITY_PF_POLICY\" \"\$SECURITY_OVERALL\""

  [ "$status" -eq 0 ]
  [ "$output" = "2|enforced|notRequired|enforced|enforced" ]
}

@test "missing malformed and symlinked summaries fail closed" {
  run bash -c "source '$SCRIPT'; security_summary_load"
  [ "$status" -ne 0 ]

  write_valid_status
  printf 'device=disk2s1\n' >> "$NTFSMAC_SECURITY_STATUS_FILE"
  run bash -c "source '$SCRIPT'; security_summary_load"
  [ "$status" -ne 0 ]

  rm "$NTFSMAC_SECURITY_STATUS_FILE"
  printf 'private target\n' > "$FIXTURE_DIR/target"
  ln -s "$FIXTURE_DIR/target" "$NTFSMAC_SECURITY_STATUS_FILE"
  run bash -c "source '$SCRIPT'; security_summary_load"
  [ "$status" -ne 0 ]
}

@test "a group-or-world-writable summary fails closed" {
  write_valid_status
  chmod 666 "$NTFSMAC_SECURITY_STATUS_FILE"

  run bash -c "source '$SCRIPT'; security_summary_load"

  [ "$status" -ne 0 ]
}
