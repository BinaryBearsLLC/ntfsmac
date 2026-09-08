#!/bin/bash
# shellcheck disable=SC2034 # Public values consumed by the JSON/human diagnostic formatters.
# Read-only platform context. Never collect model identifiers, serials, UUIDs, or hostnames.
platform_diagnostics_collect() {
  local release="$1" build="$2" architecture="$3" os="$4" manifest="$5"
  local brand virtual hv canonical_os
  MACOS_BUILD_VERSION="$(safe_version_token "${NTFSMAC_MACOS_BUILD_OVERRIDE-$(/usr/bin/sw_vers -buildVersion 2>/dev/null)}")"
  brand="${NTFSMAC_CPU_BRAND_OVERRIDE-$(/usr/sbin/sysctl -n machdep.cpu.brand_string 2>/dev/null)}"
  brand="${brand% (Virtual)}"
  if [[ "$brand" =~ ^Apple\ M[0-9]+(\ Pro|\ Max|\ Ultra)?$ ]]; then
    HARDWARE_FAMILY="${brand// /_}"
  else
    HARDWARE_FAMILY="unknown"
  fi
  virtual="${NTFSMAC_VIRTUAL_MACHINE_OVERRIDE-$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)}"
  case "$virtual" in
    0) VIRTUAL_MACHINE_JSON=false ;;
    1) VIRTUAL_MACHINE_JSON=true ;;
    *) VIRTUAL_MACHINE_JSON=null ;;
  esac
  hv="${NTFSMAC_HV_SUPPORT_OVERRIDE-$(/usr/sbin/sysctl -n kern.hv_support 2>/dev/null)}"
  case "$hv" in
    0) HYPERVISOR_SYSCTL_SUPPORT=unavailable ;;
    1) HYPERVISOR_SYSCTL_SUPPORT=available ;;
    *) HYPERVISOR_SYSCTL_SUPPORT=unknown ;;
  esac
  MACOS_VALIDATION_STATE=not_validated
  canonical_os="$(printf '%s\n' "$os" | awk -F. '
    /^[0-9]+\.[0-9]+(\.[0-9]+)?$/ { printf "%d.%d.%d", $1, $2, $3 }')"
  if [[ -n "$canonical_os" && -r "$manifest" ]] && awk \
    -v release="$release" -v build="$build" -v arch="$architecture" -v os="$canonical_os" \
    '!/^#/ && NF == 4 && $1 == release && $2 == build && $3 == arch && $4 == os { found=1 }
     END { exit !found }' "$manifest"; then
    MACOS_VALIDATION_STATE=validated
  fi
}
