#!/bin/bash
# Resolve a public tag without putting prerelease text in Apple's numeric version keys.
release_version() {
  local plist="$1" base tag label
  base=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") || return 1
  tag=$(/usr/libexec/PlistBuddy -c 'Print :NTFSMACReleaseTag' "$plist" 2>/dev/null) || tag="$base"
  label=$(/usr/libexec/PlistBuddy -c 'Print :NTFSMACReleaseLabel' "$plist" 2>/dev/null) || label=""
  [[ "$base" =~ ^3\.[0-9]+\.[0-9]+$ ]] || return 1
  if [[ "$tag" == "$base" && -z "$label" ]]; then
    printf '%s\n' "$base"
  elif [[ "$tag" =~ ^3\.[0-9]+\.[0-9]+-beta\.([1-9][0-9]*)$ &&
          "${tag%-beta.*}" == "$base" && "$label" == "Beta ${BASH_REMATCH[1]}" ]]; then
    printf '%s\n' "$tag"
  else
    echo 'release-version: inconsistent release tag/label' >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  release_version "${1:?Provide an Info.plist path}"
fi
