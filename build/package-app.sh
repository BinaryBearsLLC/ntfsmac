#!/bin/bash
# build/package-app.sh — assembles the standard or Legacy ntfsmac.app variant.
#
# Release-builds the gui + helper SPM executables, lays them into a real .app bundle, then signs
# the helper and outer app in that order. The standard build embeds an SMAppService LaunchDaemon;
# the Legacy build embeds the standalone SMJobBless helper under LaunchServices. Local builds
# default to ad-hoc; official releases supply the BinaryBears Developer ID identity and use
# Hardened Runtime plus Apple's trusted timestamp.
#
# Bundles vendor/bin/* + cli/{commands,lib,pf} + install.sh into Contents/Resources/cli-src/
# (REPO_ROOT-relative layout install.sh already expects, unchanged) — explicit product
# decision, supersedes this script's prior "CLI installed separately via install.sh/tap"
# note: `HelperService.stageCLI` now runs this same bundled install.sh, already root, right
# after a successful `SMJobBless`, so a GUI-only install is fully self-sufficient with no
# separate Terminal step. `--no-path-link` (install.sh) keeps `ntfsmac` off the user's
# Terminal PATH for this path — CLI stays reachable only via the privileged helper the GUI
# already drives, never a bare shell command, per explicit instruction.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/macos-target.sh"
macos_target_activate

HELPER_VARIANT="${NTFSMAC_HELPER_VARIANT:-modern}"
case "$HELPER_VARIANT" in
  modern | legacy) ;;
  *)
    echo "package-app: HARD-STOP — NTFSMAC_HELPER_VARIANT must be 'modern' or 'legacy'" >&2
    exit 1
    ;;
esac

SWIFT_SCRATCH_DIR="${NTFSMAC_SWIFT_SCRATCH_DIR:-$REPO_ROOT/.build/ntfsmac-$HELPER_VARIANT}"
RELEASE_DIR="${NTFSMAC_SWIFT_RELEASE_DIR:-$SWIFT_SCRATCH_DIR/release}"
OUT_DIR="${NTFSMAC_APP_OUT_DIR:-$REPO_ROOT/dist}"
if [[ "$HELPER_VARIANT" == "legacy" ]]; then
  DEFAULT_APP="$OUT_DIR/ntfsmac-legacy.app"
  HELPER_INFO_PLIST="$REPO_ROOT/helper/Info.plist"
  HELPER_LAUNCHD_PLIST="$REPO_ROOT/helper/launchd.plist"
else
  DEFAULT_APP="$OUT_DIR/ntfsmac.app"
  HELPER_INFO_PLIST="$REPO_ROOT/helper/Info-Modern.plist"
  HELPER_LAUNCHD_PLIST="$REPO_ROOT/helper/launchd-modern.plist"
fi
APP="${NTFSMAC_APP_BUNDLE_OUT:-$DEFAULT_APP}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"

GUI_BIN_NAME="ntfsmac-gui"
HELPER_BIN_NAME="ntfsmac-helper"

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

validate_product_versions() {
  local product_info="${NTFSMAC_PRODUCT_INFO_PLIST_OVERRIDE:-$REPO_ROOT/gui/Info.plist}"
  if [[ ! -r "$product_info" ]]; then
    echo "package-app: HARD-STOP — product version source missing: $product_info" >&2
    return 1
  fi

  local canonical_release canonical_build helper_release helper_build
  canonical_release="$(plist_get "$product_info" CFBundleShortVersionString)" || return 1
  canonical_build="$(plist_get "$product_info" CFBundleVersion)" || return 1
  helper_release="$(plist_get "$HELPER_INFO_PLIST" CFBundleShortVersionString)" || return 1
  helper_build="$(plist_get "$HELPER_INFO_PLIST" CFBundleVersion)" || return 1
  if [[ "$helper_release" != "$canonical_release" || "$helper_build" != "$canonical_build" ]]; then
    echo "package-app: HARD-STOP — helper version $helper_release ($helper_build) does not match app version $canonical_release ($canonical_build)" >&2
    return 1
  fi
}

swift_build_release() {
  local -a args=(-c release --package-path "$REPO_ROOT" --scratch-path "$SWIFT_SCRATCH_DIR")
  # Codex/CI may already run inside a filesystem sandbox; SwiftPM's nested sandbox cannot be
  # created there. This opt-in disables only SwiftPM's inner process sandbox, never the outer
  # runner or any repository safety gate.
  [[ "${NTFSMAC_SWIFTPM_DISABLE_SANDBOX:-}" == "1" ]] && args+=(--disable-sandbox)
  NTFSMAC_HELPER_VARIANT="$HELPER_VARIANT" swift build "${args[@]}"
}

# stage_offline_runtime <source-root> <staging-root>
# Copies the verifier, its source locks, and the complete runtime into the same
# tree install.sh will later consume. The copied tree is verified again before it
# can participate in the helper's signed content hash.
stage_offline_runtime() {
  local source_root="$1" staging_root="$2"
  local source_runtime="$source_root/vendor/runtime"
  local source_verifier="$source_root/build/verify-offline-runtime.py"
  local staged_runtime="$staging_root/vendor/runtime"
  local lock

  if [[ ! -d "$staging_root" || -L "$staging_root" ]]; then
    echo "package-app: HARD-STOP — offline runtime staging root is missing or unsafe" >&2
    return 1
  fi
  if [[ ! -d "$source_runtime" || -L "$source_runtime" ||
        ! -f "$source_verifier" || -L "$source_verifier" ]]; then
    echo "package-app: HARD-STOP — offline runtime payload or verifier is missing; reinstall the source checkout" >&2
    return 1
  fi
  if ! python3 "$source_verifier" "$source_root"; then
    echo "package-app: HARD-STOP — offline runtime source verification failed" >&2
    return 1
  fi
  if find "$source_runtime" -type l -print -quit | grep -q .; then
    echo "package-app: HARD-STOP — offline runtime payload contains a symlink" >&2
    return 1
  fi

  mkdir -p "$staging_root/build" "$staging_root/vendor" || return 1
  if [[ -e "$staged_runtime" || -L "$staged_runtime" ]]; then
    echo "package-app: HARD-STOP — offline runtime staging destination already exists" >&2
    return 1
  fi
  if ! cp "$source_verifier" "$staging_root/build/verify-offline-runtime.py"; then
    echo "package-app: HARD-STOP — failed to stage offline runtime verifier" >&2
    return 1
  fi
  chmod +x "$staging_root/build/verify-offline-runtime.py" || return 1
  for lock in sources.lock alpine-base-packages.lock alpine-packages.lock alpine-apks.lock; do
    if [[ ! -f "$source_root/build/$lock" || -L "$source_root/build/$lock" ]] ||
       ! cp "$source_root/build/$lock" "$staging_root/build/$lock"; then
      rm -rf -- "$staged_runtime"
      echo "package-app: HARD-STOP — failed to stage offline runtime lock: $lock" >&2
      return 1
    fi
  done
  if ! cp -R "$source_runtime" "$staged_runtime"; then
    rm -rf -- "$staged_runtime"
    echo "package-app: HARD-STOP — failed to stage offline runtime payload" >&2
    return 1
  fi
  if ! cmp -s "$source_verifier" "$staging_root/build/verify-offline-runtime.py" ||
     ! python3 "$source_verifier" "$staging_root"; then
    rm -rf -- "$staged_runtime"
    echo "package-app: HARD-STOP — staged offline runtime verification failed" >&2
    return 1
  fi
  echo "package-app: staged verified offline runtime payload"
}

verify_staged_native_offline_runtime() {
  local staging_root="$1"
  local native_verifier="$staging_root/vendor/bin/init-rootfs"
  local staged_runtime="$staging_root/vendor/runtime"

  if [[ ! -f "$native_verifier" || -L "$native_verifier" ]] ||
     [[ ! -d "$staged_runtime" || -L "$staged_runtime" ]]; then
    echo "package-app: HARD-STOP — staged native verifier or offline runtime payload is missing or unsafe" >&2
    return 1
  fi
  if ! /usr/bin/file "$native_verifier" | grep -q 'Mach-O' ||
     ! codesign --verify --strict "$native_verifier" >/dev/null 2>&1; then
    echo "package-app: HARD-STOP — staged offline runtime verifier is not a valid signed macOS executable" >&2
    return 1
  fi
  staged_runtime="$(cd "$staged_runtime" && pwd -P)" || {
    echo "package-app: HARD-STOP — could not canonicalize the staged offline runtime path" >&2
    return 1
  }
  if ! "$native_verifier" -verify-offline-runtime "$staged_runtime"; then
    echo "package-app: HARD-STOP — staged payload does not match the embedded offline runtime manifest" >&2
    return 1
  fi
  echo "package-app: staged payload matches the native embedded offline runtime manifest"
}

verify_filesystem_probe_cli() {
  local executable="$1" output probe_exit=0
  output="$("$executable" --help 2>&1)" || output=""
  if [[ "$output" != *"probe-filesystem"* ]]; then
    echo "package-app: HARD-STOP — native filesystem metadata command is missing; rebuild runtime" >&2
    return 1
  fi
  # An invalid identifier exercises only parsing/validation. It cannot read a disk,
  # initialize the runtime, or silently accept an older binary lacking this command.
  output="$("$executable" probe-filesystem invalid 2>&1)" || probe_exit=$?
  if [[ "$probe_exit" -ne 1 || "$output" != *"rejected: expected diskNsM partition identifier"* ]]; then
    echo "package-app: HARD-STOP — native filesystem metadata command is missing or incompatible; rebuild runtime" >&2
    return 1
  fi
}

main() {
  validate_product_versions || exit 1

  local manifest_file="$REPO_ROOT/helper/GeneratedCLIManifest.swift"
  local restore_manifest=1
  [[ -n "${NTFSMAC_KEEP_GENERATED_MANIFEST:-}" ]] && restore_manifest=0
  # `GeneratedCLIManifest.swift` gets a real hash written into it below, then this trap restores
  # the checked-in placeholder afterward so a local packaging run never leaves the working tree
  # dirty with one machine's real hash — the file's own header comment says "overwritten on
  # every real packaging run", not "committed with a real value". Restoring via a plain file
  # backup, not `git checkout --`: the manifest is a *new*, not-yet-committed file the first time
  # this runs, and `git checkout --` on an untracked path always fails ("did not match any
  # file(s) known to git") — confirmed on the first real run of this script. A backup copy works
  # regardless of git tracking state. The trap references literal, already-substituted paths
  # (not `$manifest_file`/`$REPO_ROOT` as variables) because an EXIT trap runs after `main()` has
  # already returned, outside any `local`'s scope — referencing a `local` var there trips `set
  # -u` (also confirmed on that same first run).
  if [[ "$restore_manifest" -eq 1 ]]; then
    local manifest_backup
    manifest_backup="$(mktemp)"
    cp "$manifest_file" "$manifest_backup"
    # shellcheck disable=SC2064
    trap "cp '$manifest_backup' '$manifest_file' 2>/dev/null; rm -f '$manifest_backup'" EXIT
  fi

  if [[ -z "${NTFSMAC_SKIP_SWIFT_BUILD:-}" ]]; then
    echo "package-app: swift build -c release (pass 1 — placeholder hash, hashing tool only)"
    if ! swift_build_release; then
      echo "package-app: HARD-STOP — swift build -c release (pass 1) failed" >&2
      exit 1
    fi
  fi

  local gui_bin="$RELEASE_DIR/$GUI_BIN_NAME"
  local helper_bin="$RELEASE_DIR/$HELPER_BIN_NAME"
  if [[ ! -f "$gui_bin" ]]; then
    echo "package-app: HARD-STOP — $gui_bin missing (expected swift build -c release output)" >&2
    exit 1
  fi
  if [[ ! -f "$helper_bin" ]]; then
    echo "package-app: HARD-STOP — $helper_bin missing (expected swift build -c release output)" >&2
    exit 1
  fi

  # Assemble the cli-src staging tree once, in a scratch dir, before hashing or copying it
  # anywhere — hashed here (pass-1 helper, still carrying the placeholder) and later copied
  # byte-for-byte into Contents/Resources/cli-src/, so the hash pass-2's helper ships with is
  # guaranteed to match exactly what the bundle actually contains.
  local cli_stage
  cli_stage="$(mktemp -d)"
  mkdir -p "$cli_stage/vendor/bin" "$cli_stage/vendor/kernel" "$cli_stage/cli/commands" "$cli_stage/cli/lib" "$cli_stage/cli/pf" "$cli_stage/build/lib" "$cli_stage/gui"
  stage_offline_runtime "$REPO_ROOT" "$cli_stage" || {
    rm -rf -- "$cli_stage"
    exit 1
  }
  if ! cp "$REPO_ROOT/install.sh" "$cli_stage/install.sh"; then
    echo "package-app: HARD-STOP — failed to stage install.sh" >&2
    exit 1
  fi
  chmod +x "$cli_stage/install.sh"
  if ! cp "$REPO_ROOT"/vendor/bin/* "$cli_stage/vendor/bin/"; then
    echo "package-app: HARD-STOP — failed to stage vendor/bin/*" >&2
    exit 1
  fi
  if ! cp "$REPO_ROOT"/cli/commands/*.sh "$cli_stage/cli/commands/"; then
    echo "package-app: HARD-STOP — failed to stage cli/commands/*.sh" >&2
    exit 1
  fi
  if ! cp "$REPO_ROOT"/cli/lib/*.sh "$cli_stage/cli/lib/"; then
    echo "package-app: HARD-STOP — failed to stage cli/lib/*.sh" >&2
    exit 1
  fi
  cp "$REPO_ROOT/cli/lib/macos-validated-builds.txt" "$cli_stage/cli/lib/" || exit 1
  if ! cp "$REPO_ROOT"/cli/pf/*.tmpl "$cli_stage/cli/pf/"; then
    echo "package-app: HARD-STOP — failed to stage cli/pf/*.tmpl" >&2
    exit 1
  fi
  if ! cp "$REPO_ROOT/gui/Info.plist" "$cli_stage/gui/Info.plist"; then
    echo "package-app: HARD-STOP — failed to stage canonical gui/Info.plist" >&2
    exit 1
  fi
  if ! cp "$REPO_ROOT/build/sources.lock" "$cli_stage/build/sources.lock"; then
    echo "package-app: HARD-STOP — failed to stage build/sources.lock" >&2
    exit 1
  fi
  if ! cp "$REPO_ROOT/build/lib/lock.sh" "$cli_stage/build/lib/lock.sh"; then
    echo "package-app: HARD-STOP — failed to stage build/lib/lock.sh" >&2
    exit 1
  fi
  if [[ -d "$REPO_ROOT/vendor/kernel" ]]; then
    cp "$REPO_ROOT"/vendor/kernel/* "$cli_stage/vendor/kernel/" 2>/dev/null || true
  fi

  # P0 trust gate: inspect the exact binaries/tree about to be hashed and bundled. A release
  # carrying a floating alpine:latest fallback is rejected before the helper manifest is baked.
  if ! NTFSMAC_SOURCES_LOCK="$cli_stage/build/sources.lock" \
    NTFSMAC_VENDOR_BIN_DIR="$cli_stage/vendor/bin" \
    NTFSMAC_SHIPPED_TREE="$cli_stage" "$REPO_ROOT/build/verify-runtime-alpine.sh"; then
    echo "package-app: HARD-STOP — staged runtime Alpine pin verification failed" >&2
    rm -rf "$cli_stage"
    exit 1
  fi
  verify_staged_native_offline_runtime "$cli_stage" || {
    rm -rf -- "$cli_stage"
    exit 1
  }
  verify_filesystem_probe_cli "$cli_stage/vendor/bin/anylinuxfs" || {
    rm -rf -- "$cli_stage"
    exit 1
  }

  echo "package-app: computing cli-src content hash (pass-1 helper binary as a hashing tool)"
  macos_target_verify_runtime "$cli_stage/vendor/bin" || exit 1
  local tree_hash
  tree_hash="$("$helper_bin" --print-tree-hash "$cli_stage")" || {
    echo "package-app: HARD-STOP — failed to compute cli-src tree hash" >&2
    rm -rf "$cli_stage"
    exit 1
  }
  if [[ -z "$tree_hash" ]]; then
    echo "package-app: HARD-STOP — empty cli-src tree hash" >&2
    rm -rf "$cli_stage"
    exit 1
  fi

  echo "package-app: pinning cli-src hash into GeneratedCLIManifest.swift ($tree_hash)"
  cat > "$manifest_file" <<SWIFT
/// Auto-generated by build/package-app.sh — DO NOT EDIT BY HAND, overwritten on every real
/// packaging run (and restored to the checked-in placeholder afterward). SHA-256 tree hash of
/// Contents/Resources/cli-src/ exactly as staged for this build.
public enum GeneratedCLIManifest {
    public static let expectedTreeHashHex = "$tree_hash"
}
SWIFT
  # This repo lives on an SMB-mounted network share (confirmed elsewhere this session to have
  # coarse/laggy mtime resolution — the same class of issue that broke `swift test`'s generated
  # test-runner scaffold earlier). Writing this file and immediately invoking `swift build`
  # reproducibly hit "input file was modified during the build" here, every time — `sync` plus a
  # short settle gives the network mount's mtime a moment to catch up before SPM stats the file.
  sync
  sleep 1

  if [[ -z "${NTFSMAC_SKIP_SWIFT_BUILD:-}" ]]; then
    echo "package-app: swift build -c release (pass 2 — real hash baked into the shipped helper)"
    if ! swift_build_release; then
      echo "package-app: HARD-STOP — swift build -c release (pass 2) failed" >&2
      rm -rf "$cli_stage"
      exit 1
    fi
  else
    # Fixture tests inject already-built Mach-O binaries (including a helper that implements
    # --print-tree-hash). Skipping pass 1 must skip pass 2 too; otherwise the test unexpectedly
    # invokes the host Swift toolchain but still packages the injected binaries from RELEASE_DIR.
    echo "package-app: swift build skipped — using injected release binaries"
  fi
  # Re-read: pass 2 rebuilt both binaries at the same $RELEASE_DIR paths — $helper_bin now
  # carries the real pinned hash, this is the one that actually gets signed and installed below.

  local helper_label
  helper_label="$(plist_get "$HELPER_INFO_PLIST" CFBundleIdentifier)" || {
    echo "package-app: HARD-STOP — couldn't read CFBundleIdentifier from $HELPER_INFO_PLIST" >&2
    exit 1
  }
  # helper_label becomes a path component below (Contents/Library/LaunchServices/$helper_label)
  # and a codesign --identifier value — reject anything that isn't a plain bundle-id-shaped
  # token before it touches a path, same discipline as the `^disk[0-9]+s[0-9]+$` device-name
  # check CLAUDE.md requires before any shell invocation.
  if [[ ! "$helper_label" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
    echo "package-app: HARD-STOP — helper/Info.plist CFBundleIdentifier '$helper_label' is not a safe path component" >&2
    exit 1
  fi

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  if [[ "$HELPER_VARIANT" == "legacy" ]]; then
    mkdir -p "$APP/Contents/Library/LaunchServices"
    helper_destination="$APP/Contents/Library/LaunchServices/$helper_label"
  else
    mkdir -p "$APP/Contents/Library/LaunchDaemons"
    helper_destination="$APP/Contents/Resources/$HELPER_BIN_NAME"
  fi

  if ! cp "$gui_bin" "$APP/Contents/MacOS/$GUI_BIN_NAME"; then
    echo "package-app: HARD-STOP — failed to copy $gui_bin" >&2
    exit 1
  fi
  if ! cp "$REPO_ROOT/gui/Info.plist" "$APP/Contents/Info.plist"; then
    echo "package-app: HARD-STOP — failed to copy gui/Info.plist" >&2
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Delete :NTFSMACHelperVariant" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :NTFSMACHelperVariant string $HELPER_VARIANT" "$APP/Contents/Info.plist" || {
    echo "package-app: HARD-STOP — failed to record helper variant in app Info.plist" >&2
    exit 1
  }
  if [[ "$HELPER_VARIANT" == "modern" ]]; then
    /usr/libexec/PlistBuddy -c "Delete :SMPrivilegedExecutables" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
    if ! cp "$HELPER_LAUNCHD_PLIST" "$APP/Contents/Library/LaunchDaemons/$helper_label.plist"; then
      echo "package-app: HARD-STOP — failed to embed the SMAppService LaunchDaemon plist" >&2
      exit 1
    fi
  fi
  if ! cp "$REPO_ROOT/gui/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; then
    echo "package-app: HARD-STOP — failed to copy gui/Resources/AppIcon.icns" >&2
    exit 1
  fi
  if ! cp "$REPO_ROOT/gui/Resources/HelperIcon.png" "$APP/Contents/Resources/HelperIcon.png"; then
    echo "package-app: HARD-STOP — failed to copy gui/Resources/HelperIcon.png" >&2
    exit 1
  fi
  if ! cp "$helper_bin" "$helper_destination"; then
    echo "package-app: HARD-STOP — failed to copy $helper_bin" >&2
    exit 1
  fi

  # Copied from $cli_stage (already assembled + hashed above), not re-read from $REPO_ROOT — this
  # guarantees the bundle's actual content is byte-for-byte what GeneratedCLIManifest.swift's
  # pinned hash was computed over.
  local cli_src="$APP/Contents/Resources/cli-src"
  if ! cp -R "$cli_stage/." "$cli_src"; then
    echo "package-app: HARD-STOP — failed to copy staged cli-src into the bundle" >&2
    rm -rf "$cli_stage"
    exit 1
  fi
  rm -rf "$cli_stage"

  local -a helper_sign_args=(-s "$SIGNING_IDENTITY" --force --timestamp=none --identifier "$helper_label")
  macos_target_verify_binary "$APP/Contents/MacOS/$GUI_BIN_NAME" || exit 1
  macos_target_verify_binary "$helper_destination" || exit 1
  local -a app_sign_args=(-s "$SIGNING_IDENTITY" --force --timestamp=none)
  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    helper_sign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --identifier "$helper_label")
    app_sign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp)
    if [[ -n "$SIGNING_KEYCHAIN" ]]; then
      helper_sign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --keychain "$SIGNING_KEYCHAIN" --identifier "$helper_label")
      app_sign_args=(-s "$SIGNING_IDENTITY" --force --options runtime --timestamp --keychain "$SIGNING_KEYCHAIN")
    fi
  fi

  echo "package-app: signing helper binary with $SIGNING_IDENTITY"
  if ! codesign "${helper_sign_args[@]}" "$helper_destination" 2>&1; then
    echo "package-app: HARD-STOP — failed to sign helper binary" >&2
    exit 1
  fi

  # The gui binary is intentionally not signed standalone here: it has no adjacent Info.plist
  # at this point (no meaningful identifier to set), and the outer-bundle sign below fully
  # re-signs it anyway once Contents/Info.plist is in place.
  echo "package-app: signing outer bundle with $SIGNING_IDENTITY"
  if ! codesign "${app_sign_args[@]}" "$APP" 2>&1; then
    echo "package-app: HARD-STOP — failed to sign $APP" >&2
    exit 1
  fi

  echo "package-app: done — $APP"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
