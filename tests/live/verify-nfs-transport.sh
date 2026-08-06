#!/bin/bash
# Read-only packaged-app gate for the vmnet-only NFS transport contract. It emits only counts and
# fixed result tokens: no device name, volume label, mount path, hostname, address, route, or PID.
set -euo pipefail

fail() {
  printf 'verify-nfs-transport: FAIL — %s\n' "$1" >&2
  exit 1
}

if [[ "${NTFSMAC_LIVE_PLATFORM_OVERRIDE-$(uname -s)}" != "Darwin" ]]; then
  fail "macOS is required"
fi

mount_output="${NTFSMAC_LIVE_MOUNT_OUTPUT-$(/sbin/mount -t nfs 2>/dev/null)}"
[[ -n "$mount_output" ]] || fail "no active NFS mounts"
nfsstat_output="${NTFSMAC_LIVE_NFSSTAT_OUTPUT-$(/usr/bin/nfsstat -m 2>/dev/null)}"

vmnet_running="${NTFSMAC_LIVE_VMNET_RUNNING_OVERRIDE-}"
if [[ -z "$vmnet_running" ]]; then
  pgrep -x vmnet-helper >/dev/null 2>&1 && vmnet_running=1 || vmnet_running=0
fi
[[ "$vmnet_running" == "1" ]] || fail "vmnet-helper is not active"

gvproxy_running="${NTFSMAC_LIVE_GVPROXY_RUNNING_OVERRIDE-}"
if [[ -z "$gvproxy_running" ]]; then
  pgrep -x gvproxy >/dev/null 2>&1 && gvproxy_running=1 || gvproxy_running=0
fi
[[ "$gvproxy_running" == "0" ]] || fail "gvproxy loopback transport is active"

listener_count="${NTFSMAC_LIVE_LOOPBACK_LISTENER_COUNT_OVERRIDE-}"
if [[ -z "$listener_count" ]]; then
  if /usr/sbin/lsof -nP -iTCP@127.0.0.1:2049 -sTCP:LISTEN >/dev/null 2>&1 || \
     /usr/sbin/lsof -nP -iUDP@127.0.0.1:2049 >/dev/null 2>&1; then
    listener_count=1
  else
    listener_count=0
  fi
fi
[[ "$listener_count" == "0" ]] || fail "a loopback NFS listener is active"

checked=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  source="${line%% on *}"
  [[ "$source" != "$line" ]] || continue
  host="${source%%:*}"

  # ntfsmac normally uses `<device>.local`; raw addresses are accepted only when they fall inside
  # the audited anylinuxfs vmnet pool, covering mDNS registration fallback without broadening the
  # contract to arbitrary private networks.
  is_ntfsmac=0
  if [[ "$host" =~ ^disk[0-9]+s[0-9]+(-[0-9]+)?\.local$ ]]; then
    is_ntfsmac=1
  elif [[ "$host" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+$ ]]; then
    is_ntfsmac=1
  fi
  [[ "$is_ntfsmac" -eq 1 ]] || continue

  mount_point="${line#* on }"
  mount_point="${mount_point%% (nfs*}"
  if ! awk -v header="$mount_point from $source" '
    $0 == header { in_mount = 1; next }
    in_mount && $0 !~ /^[[:space:]]/ { exit }
    in_mount && /NFS parameters:/ {
      parameters = $0
      gsub(/[[:space:]]/, "", parameters)
      if (parameters ~ /(^|,)soft(,|$)/) soft = 1
    }
    END { exit soft ? 0 : 1 }
  ' <<< "$nfsstat_output"; then
    fail "an ntfsmac NFS mount is not soft"
  fi

  resolved="${NTFSMAC_LIVE_RESOLVED_IP_OVERRIDE-}"
  if [[ -z "$resolved" ]]; then
    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      resolved="$host"
    else
      resolved="$(/usr/bin/dscacheutil -q host -a name "$host" 2>/dev/null | awk '/^ip_address: / { print $2; exit }')"
    fi
  fi
  [[ "$resolved" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+$ ]] \
    || fail "an ntfsmac endpoint is outside the vmnet pool"

  route_interface="${NTFSMAC_LIVE_ROUTE_INTERFACE_OVERRIDE-}"
  if [[ -z "$route_interface" ]]; then
    route_interface="$(/sbin/route -n get "$resolved" 2>/dev/null | awk '/interface:/{print $2; exit}')"
  fi
  [[ "$route_interface" == bridge* ]] || fail "the NFS endpoint is not routed through vmnet"
  checked=$((checked + 1))
done <<< "$mount_output"

[[ "$checked" -gt 0 ]] || fail "no ntfsmac-owned NFS mount was identified"
printf 'verify-nfs-transport: PASS — %s ntfsmac mount(s), vmnet/private/soft, no loopback listener\n' "$checked"
