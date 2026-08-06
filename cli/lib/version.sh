#!/bin/bash
# shellcheck disable=SC2034 # sourced public API: callers consume these resolved variables
# Resolves product/build metadata from the app Info.plist. gui/Info.plist is the single source of
# truth in a source/package tree; install.sh copies that exact plist beside this script as
# product-info.plist so a standalone installed CLI reports the same build without hard-coded
# shell constants or requiring the .app to remain installed.
NTFSMAC_DIAGNOSTIC_SCHEMA_VERSION="5"

ntfsmac_load_product_version() {
  local repo_root="$1"
  local lib_dir product_info
  lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
  product_info="${NTFSMAC_PRODUCT_INFO_PLIST_OVERRIDE-}"

  if [[ -z "$product_info" && -r "$repo_root/gui/Info.plist" ]]; then
    product_info="$repo_root/gui/Info.plist"
  elif [[ -z "$product_info" && -r "$lib_dir/product-info.plist" ]]; then
    product_info="$lib_dir/product-info.plist"
  fi

  NTFSMAC_VERSION="unknown"
  NTFSMAC_BUILD_VERSION="unknown"
  if [[ -n "$product_info" && -r "$product_info" ]]; then
    NTFSMAC_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$product_info" 2>/dev/null || printf 'unknown')"
    NTFSMAC_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$product_info" 2>/dev/null || printf 'unknown')"
  fi
}
