#!/bin/bash
# Interactive source-build assistant for ntfsmac.
# Double-click this file in Finder, or run it as ./build.command [cli|gui|both] [--no-legacy].
# GUI targets always use the versioned BinaryBears installer assets from build/dmg-assets/.
# Missing build tools are installed only after explicit user consent.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DIST_DIR="$REPO_ROOT/dist"
BINARYBEARS_SIGNING_IDENTITY="Developer ID Application: BinaryBears LLC (SQY8T23X8N)"
INTERACTIVE=0
TARGET=""
LEGACY_ENABLED=1

if [[ -t 1 && -n "${TERM:-}" ]] && command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold 2>/dev/null || true)"
  DIM="$(tput dim 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"
  YELLOW="$(tput setaf 3 2>/dev/null || true)"
  RED="$(tput setaf 1 2>/dev/null || true)"
  BLUE="$(tput setaf 4 2>/dev/null || true)"
  RESET="$(tput sgr0 2>/dev/null || true)"
else
  BOLD=""
  DIM=""
  GREEN=""
  YELLOW=""
  RED=""
  BLUE=""
  RESET=""
fi

banner() {
  printf '%s\n' "+------------------------------------------------------------+"
  printf '|%s%-60s%s|\n' "$BOLD$BLUE" "             NTFSMAC SOURCE BUILD ASSISTANT" "$RESET"
  printf '|%-60s|\n' " Apple Silicon CLI + self-contained macOS menu-bar app"
  printf '%s\n' "+------------------------------------------------------------+"
}

section() {
  echo ""
  printf '%s==> %s%s\n' "$BOLD$BLUE" "$1" "$RESET"
  printf '%s\n' "--------------------------------------------------------------"
}

ok() {
  printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$1"
}

warn() {
  printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$1"
}

info() {
  printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$1"
}

pause_if_interactive() {
  if [[ "$INTERACTIVE" -eq 1 && -t 0 ]]; then
    echo ""
    read -r -p "Press Return to close this window..." _unused
  fi
}

fail() {
  echo ""
  printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$1" >&2
  pause_if_interactive
  exit 1
}

confirm() {
  local prompt="$1" answer
  if [[ ! -t 0 ]]; then
    warn "Automatic installation needs an interactive Terminal."
    return 1
  fi
  read -r -p "$prompt [y/N]: " answer
  case "$answer" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: ./build.command [cli|gui|both] [--no-legacy]

  cli   Build and verify the CLI runtime, then create
        dist/ntfsmac-cli.tar.gz
  gui   Build the shared CLI runtime, run the Swift tests, then create and
        verify the branded standard and Legacy app/DMG distributions
  both  Create and verify both distributions in one run

  --no-legacy  Build only the standard modern-helper app/DMG. By default every
               GUI build automatically produces both standard and Legacy variants.

With no argument, an interactive menu is shown. Missing command-line build
dependencies can be installed only after an explicit confirmation. Full Xcode
must be installed through Apple; the helper can open its App Store page.
If the official BinaryBears Developer ID identity is installed, GUI builds use it
automatically so the local standard helper can be exercised. Otherwise the builder emits
an explicit warning and creates an ad-hoc inspection build; SIGNING_IDENTITY=- also
forces that fallback deliberately.
Nothing is installed into /usr/local by this build helper.
EOF
}

choose_legacy_mode() {
  [[ "$TARGET" == "gui" || "$TARGET" == "both" ]] || return
  local answer
  echo ""
  read -r -p "Also build the Legacy compatibility version? [Y/n]: " answer
  case "$answer" in
    n | N | no | NO | No) LEGACY_ENABLED=0 ;;
    *) LEGACY_ENABLED=1 ;;
  esac
}

choose_target() {
  banner
  echo ""
  printf '  %s1%s  Build CLI software\n' "$BOLD" "$RESET"
  printf '  %s2%s  Build GUI app and DMG\n' "$BOLD" "$RESET"
  printf '  %s3%s  Build both distributions\n' "$BOLD" "$RESET"
  echo ""
  read -r -p "Select 1, 2, or 3: " choice

  case "$choice" in
    1) TARGET="cli" ;;
    2) TARGET="gui" ;;
    3) TARGET="both" ;;
    *) fail "Invalid selection '$choice'." ;;
  esac
}

set_homebrew_path() {
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
  fi
  if command -v brew >/dev/null 2>&1; then
    local llvm_prefix
    llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
    if [[ -n "$llvm_prefix" && -d "$llvm_prefix/bin" ]]; then
      export PATH="$llvm_prefix/bin:$PATH"
    fi
  fi
}

check_platform() {
  section "Platform checks"

  local arch macos_version macos_major
  arch="$(uname -m)"
  [[ "$arch" == "arm64" ]] || fail "ntfsmac supports Apple Silicon only; detected $arch."
  ok "Architecture: $arch"

  macos_version="$(sw_vers -productVersion 2>/dev/null || true)"
  macos_major="${macos_version%%.*}"
  if [[ ! "$macos_major" =~ ^[0-9]+$ || "$macos_major" -lt 13 ]]; then
    fail "macOS 13.0 or newer is required; detected ${macos_version:-unknown}."
  fi
  ok "macOS: $macos_version"
}

ensure_command_line_tools() {
  if xcode-select -p >/dev/null 2>&1 && command -v codesign >/dev/null 2>&1; then
    ok "Apple command-line tools are available"
    return
  fi

  warn "Apple command-line tools are missing."
  if confirm "Open Apple's Command Line Tools installer now?"; then
    xcode-select --install >/dev/null 2>&1 || true
    fail "Complete the Apple installer, then run build.command again."
  fi
  fail "Apple command-line tools are required."
}

ensure_full_xcode() {
  [[ "$TARGET" == "gui" || "$TARGET" == "both" ]] || return

  section "GUI toolchain checks"

  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  case "$developer_dir" in
    *Xcode*.app/Contents/Developer)
      ;;
    *)
      if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
        warn "Full Xcode is installed but is not the selected developer toolchain."
        if confirm "Select /Applications/Xcode.app for this Mac now?"; then
          sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer || \
            fail "xcode-select could not select the full Xcode toolchain."
          developer_dir="$(xcode-select -p 2>/dev/null || true)"
        else
          fail "The GUI build requires the full Xcode toolchain."
        fi
      else
        warn "Full Xcode is not installed. Command Line Tools alone are not enough for the GUI build."
        if confirm "Open the official Xcode page in the Mac App Store?"; then
          open "macappstore://itunes.apple.com/app/id497799835" || \
            fail "The Mac App Store could not be opened."
          fail "Install Xcode, open it once, then run build.command again."
        fi
        fail "Install full Xcode before building the GUI."
      fi
      ;;
  esac

  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    warn "Xcode still needs to install or approve its first-launch components."
    if confirm "Run Xcode's official first-launch setup now?"; then
      sudo xcodebuild -runFirstLaunch || fail "Xcode first-launch setup did not complete."
    else
      fail "Open Xcode once and complete its first-launch setup before continuing."
    fi
  fi

  xcodebuild -version >/dev/null 2>&1 || fail "xcodebuild is not ready. Open Xcode once and accept Apple's license."
  xcrun --find swift >/dev/null 2>&1 || fail "Swift was not found in the selected Xcode toolchain."
  xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || fail "The macOS SDK is missing from Xcode."
  command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is missing from macOS."

  ok "Selected Xcode: $developer_dir"
  ok "Swift: $(xcrun swift --version 2>&1 | head -1)"
  ok "macOS SDK: $(xcrun --sdk macosx --show-sdk-path)"
  ok "DMG tooling: hdiutil"
}

install_homebrew() {
  local installer
  installer="$(mktemp)" || fail "Could not create a temporary Homebrew installer file."
  info "Downloading Homebrew's official installer over HTTPS"
  if ! curl --fail --show-error --silent --location \
    --proto '=https' --tlsv1.2 \
    "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" \
    --output "$installer"; then
    rm -f "$installer"
    fail "Homebrew's installer could not be downloaded."
  fi
  [[ -s "$installer" ]] || {
    rm -f "$installer"
    fail "Homebrew's downloaded installer is empty."
  }
  info "Homebrew installer SHA-256: $(shasum -a 256 "$installer" | awk '{print $1}')"

  # Homebrew needs administrator access to create its Apple Silicon prefix. Its
  # NONINTERACTIVE mode deliberately refuses to open a sudo password prompt, so
  # authorize sudo first while this parent Terminal is still interactive. The
  # installer can then reuse the short-lived credential cache without silently
  # treating an administrator as an unprivileged user.
  info "Homebrew needs administrator authorization to create /opt/homebrew"
  sudo -v || {
    rm -f "$installer"
    fail "Administrator authorization was denied or is unavailable."
  }

  NONINTERACTIVE=1 /bin/bash "$installer" || {
    rm -f "$installer"
    fail "Homebrew installation failed."
  }
  rm -f "$installer"
  set_homebrew_path
  command -v brew >/dev/null 2>&1 || fail "Homebrew installed, but brew is still not available on PATH."
}

ensure_homebrew() {
  set_homebrew_path
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew: $(brew --version | head -1)"
    return
  fi

  warn "Homebrew is required by the pinned build toolchain and was not found."
  info "Installer source: https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  if confirm "Download and run the official Homebrew installer?"; then
    install_homebrew
    ok "Homebrew installed"
  else
    fail "Homebrew is required to continue."
  fi
}

ensure_brew_packages() {
  local package missing_packages
  local missing=()
  local required=(llvm lld umoci xz util-linux gettext pkg-config go)

  for package in "${required[@]}"; do
    if ! brew list --versions "$package" >/dev/null 2>&1; then
      missing+=("$package")
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    ok "Homebrew build packages are installed"
    set_homebrew_path
    return
  fi

  missing_packages="${missing[*]}"
  warn "Missing Homebrew packages: $missing_packages"
  if confirm "Install these build packages automatically?"; then
    brew install "${missing[@]}" || fail "Homebrew could not install all required packages."
    set_homebrew_path
    ok "Homebrew build packages installed"
  else
    fail "Install the missing Homebrew packages before continuing."
  fi
}

load_cargo_path() {
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  else
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
}

install_rustup() {
  local installer
  installer="$(mktemp)" || fail "Could not create a temporary Rust installer file."
  info "Downloading rustup's official installer over HTTPS"
  if ! curl --fail --show-error --silent --location \
    --proto '=https' --tlsv1.2 \
    "https://sh.rustup.rs" --output "$installer"; then
    rm -f "$installer"
    fail "rustup's installer could not be downloaded."
  fi
  [[ -s "$installer" ]] || {
    rm -f "$installer"
    fail "rustup's downloaded installer is empty."
  }
  info "rustup installer SHA-256: $(shasum -a 256 "$installer" | awk '{print $1}')"
  /bin/sh "$installer" -y --profile minimal || {
    rm -f "$installer"
    fail "Rust installation failed."
  }
  rm -f "$installer"
  load_cargo_path
}

ensure_rust_toolchain() {
  load_cargo_path
  if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1 || ! command -v rustup >/dev/null 2>&1; then
    warn "The rustup-managed Rust toolchain was not found."
    info "Installer source: https://sh.rustup.rs"
    if confirm "Download and install the official minimal Rust toolchain?"; then
      install_rustup
    else
      fail "Rust, Cargo, and rustup are required to continue."
    fi
  fi

  command -v cargo >/dev/null 2>&1 || fail "cargo is still missing after Rust setup."
  command -v rustc >/dev/null 2>&1 || fail "rustc is still missing after Rust setup."
  command -v rustup >/dev/null 2>&1 || fail "rustup is required to manage the Linux ARM64 target."

  if ! rustup target list --installed | grep -qx 'aarch64-unknown-linux-musl'; then
    warn "Rust target aarch64-unknown-linux-musl is missing."
    if confirm "Install the required Rust target automatically?"; then
      rustup target add aarch64-unknown-linux-musl || fail "The Rust Linux ARM64 target could not be installed."
    else
      fail "The Rust Linux ARM64 target is required to build vmproxy."
    fi
  fi

  ok "Rust: $(rustc --version)"
  ok "Cargo: $(cargo --version)"
  ok "Rust target: aarch64-unknown-linux-musl"
}

prepare_toolchain() {
  section "Build dependency audit"
  ensure_command_line_tools
  ensure_full_xcode
  ensure_homebrew
  ensure_brew_packages
  ensure_rust_toolchain

  section "Project preflight"
  "$REPO_ROOT/build/preflight.sh" || fail "Project preflight failed. Review the FAIL rows above."
  ok "Project preflight passed"
}

configure_gui_signing() {
  [[ "$TARGET" == "gui" || "$TARGET" == "both" ]] || return

  section "GUI signing mode"
  if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
      warn "Ad-hoc signing was explicitly requested. The DMG can be inspected, but its standard helper cannot be registered by macOS."
    else
      info "Using the explicitly configured signing identity: $SIGNING_IDENTITY"
    fi
    return
  fi

  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq -- "\"$BINARYBEARS_SIGNING_IDENTITY\""; then
    export SIGNING_IDENTITY="$BINARYBEARS_SIGNING_IDENTITY"
    ok "BinaryBears Developer ID found; app, helper, and DMG will be signed for a real local standard-helper install"
    return
  fi

  export SIGNING_IDENTITY="-"
  warn "BinaryBears Developer ID not found; falling back to an ad-hoc inspection build."
  warn "macOS will not register the standard helper from this DMG. Use an official signed/notarized release for an installation test."
}

build_runtime() {
  section "Shared CLI runtime build"
  info "Initializing the pinned anylinuxfs submodule and building the vendored runtime"
  "$REPO_ROOT/setup.sh" || fail "The shared CLI runtime build did not complete."

  section "Runtime verification"
  "$REPO_ROOT/build/verify-vendor.sh" || fail "Vendored runtime verification failed."
  ok "Vendored binaries, signatures, architecture, quarantine state, and kernel pin verified"
}

package_cli() {
  section "CLI distribution"
  mkdir -p "$DIST_DIR" || fail "Could not create $DIST_DIR."
  tar -czf "$DIST_DIR/ntfsmac-cli.tar.gz" \
    -C "$REPO_ROOT" \
    install.sh vendor cli build/sources.lock build/lib/lock.sh || \
    fail "The CLI archive could not be created."
  tar -tzf "$DIST_DIR/ntfsmac-cli.tar.gz" >/dev/null || fail "The CLI archive failed its integrity check."
  ok "CLI archive created and readable"
  "$REPO_ROOT/build/write-sha256.sh" "$DIST_DIR/ntfsmac-cli.tar.gz" || \
    fail "The CLI archive checksum could not be written and verified."
  ok "CLI SHA-256 sidecar created and verified"
}

package_gui() {
  local version modern_app modern_dmg legacy_app legacy_dmg signature_description
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")"
  modern_app="$DIST_DIR/ntfsmac.app"
  modern_dmg="$DIST_DIR/ntfsmac-${version}-Apple-Silicon.dmg"
  legacy_app="$DIST_DIR/ntfsmac-legacy.app"
  legacy_dmg="$DIST_DIR/ntfsmac-${version}-Legacy-Apple-Silicon.dmg"
  signature_description="ad-hoc"
  [[ "${SIGNING_IDENTITY:--}" != "-" ]] && signature_description="Developer ID"

  if [[ "$LEGACY_ENABLED" -eq 0 ]]; then
    # An explicit opt-out must not leave a prior Legacy build looking like part of this run.
    rm -rf -- "$legacy_app"
    rm -f -- "$legacy_dmg" "${legacy_dmg}.sha256"
  fi

  section "Swift GUI tests — standard"
  "$REPO_ROOT/build/run-swift-tests.sh" modern \
    "$REPO_ROOT/.build/ntfsmac-modern-tests" || fail "The standard Swift test suite failed."
  ok "Standard Swift tests passed"

  if [[ "$LEGACY_ENABLED" -eq 1 ]]; then
    section "Swift GUI tests — Legacy"
    "$REPO_ROOT/build/run-swift-tests.sh" legacy \
      "$REPO_ROOT/.build/ntfsmac-legacy-tests" || fail "The Legacy Swift test suite failed."
    ok "Legacy Swift tests passed"
  fi

  section "App bundle packaging — standard"
  NTFSMAC_HELPER_VARIANT=modern NTFSMAC_APP_BUNDLE_OUT="$modern_app" \
    "$REPO_ROOT/build/package-app.sh" || fail "The standard app bundle could not be created."
  [[ -d "$modern_app" ]] || fail "The expected app bundle is missing: $modern_app"
  [[ -f "$modern_app/Contents/Library/LaunchDaemons/com.binarybears.ntfsmac.helper.daemon.plist" ]] || \
    fail "The standard app is missing its SMAppService LaunchDaemon plist."
  [[ -f "$modern_app/Contents/Resources/ntfsmac-helper" ]] || \
    fail "The standard app is missing its bundled helper."
  codesign --verify --deep --strict --verbose=2 "$modern_app" || fail "The standard app signature verification failed."
  file "$modern_app/Contents/MacOS/ntfsmac-gui" | grep -q 'arm64' || fail "The standard GUI executable is not arm64."
  ok "Standard app structure, architecture, and $signature_description signature verified"

  section "DMG packaging — standard"
  NTFSMAC_APP_BUNDLE="$modern_app" NTFSMAC_DMG_OUT="$modern_dmg" \
    NTFSMAC_DMG_VOLUME_NAME="ntfsmac Installer" "$REPO_ROOT/build/make-dmg.sh" || \
    fail "The standard DMG could not be created."
  hdiutil verify "$modern_dmg" || fail "The standard DMG failed hdiutil verification."
  ok "Standard DMG created and verified"
  "$REPO_ROOT/build/write-sha256.sh" "$modern_dmg" || \
    fail "The standard DMG checksum could not be written and verified."
  ok "Standard DMG SHA-256 sidecar created and verified"

  if [[ "$LEGACY_ENABLED" -eq 1 ]]; then
    section "App bundle packaging — Legacy"
    NTFSMAC_HELPER_VARIANT=legacy NTFSMAC_APP_BUNDLE_OUT="$legacy_app" \
      "$REPO_ROOT/build/package-app.sh" || fail "The Legacy app bundle could not be created."
    [[ -d "$legacy_app" ]] || fail "The expected Legacy app bundle is missing: $legacy_app"
    [[ -f "$legacy_app/Contents/Library/LaunchServices/com.binarybears.ntfsmac.helper" ]] || \
      fail "The Legacy app is missing its SMJobBless helper."
    codesign --verify --deep --strict --verbose=2 "$legacy_app" || fail "The Legacy app signature verification failed."
    file "$legacy_app/Contents/MacOS/ntfsmac-gui" | grep -q 'arm64' || fail "The Legacy GUI executable is not arm64."
    ok "Legacy app structure, architecture, and $signature_description signature verified"

    section "DMG packaging — Legacy"
    NTFSMAC_APP_BUNDLE="$legacy_app" NTFSMAC_DMG_OUT="$legacy_dmg" \
      NTFSMAC_DMG_VOLUME_NAME="ntfsmac Legacy Installer" "$REPO_ROOT/build/make-dmg.sh" || \
      fail "The Legacy DMG could not be created."
    hdiutil verify "$legacy_dmg" || fail "The Legacy DMG failed hdiutil verification."
    ok "Legacy DMG created and verified"
    "$REPO_ROOT/build/write-sha256.sh" "$legacy_dmg" || \
      fail "The Legacy DMG checksum could not be written and verified."
    ok "Legacy DMG SHA-256 sidecar created and verified"
  fi
}

print_summary() {
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")"
  section "Build complete"
  case "$TARGET" in
    cli)
      ok "$DIST_DIR/ntfsmac-cli.tar.gz"
      ok "$DIST_DIR/ntfsmac-cli.tar.gz.sha256"
      ;;
    gui)
      ok "$DIST_DIR/ntfsmac.app"
      ok "$DIST_DIR/ntfsmac-${version}-Apple-Silicon.dmg"
      ok "$DIST_DIR/ntfsmac-${version}-Apple-Silicon.dmg.sha256"
      if [[ "$LEGACY_ENABLED" -eq 1 ]]; then
        ok "$DIST_DIR/ntfsmac-legacy.app"
        ok "$DIST_DIR/ntfsmac-${version}-Legacy-Apple-Silicon.dmg"
        ok "$DIST_DIR/ntfsmac-${version}-Legacy-Apple-Silicon.dmg.sha256"
      fi
      ;;
    both)
      ok "$DIST_DIR/ntfsmac-cli.tar.gz"
      ok "$DIST_DIR/ntfsmac-cli.tar.gz.sha256"
      ok "$DIST_DIR/ntfsmac.app"
      ok "$DIST_DIR/ntfsmac-${version}-Apple-Silicon.dmg"
      ok "$DIST_DIR/ntfsmac-${version}-Apple-Silicon.dmg.sha256"
      if [[ "$LEGACY_ENABLED" -eq 1 ]]; then
        ok "$DIST_DIR/ntfsmac-legacy.app"
        ok "$DIST_DIR/ntfsmac-${version}-Legacy-Apple-Silicon.dmg"
        ok "$DIST_DIR/ntfsmac-${version}-Legacy-Apple-Silicon.dmg.sha256"
      fi
      ;;
  esac
  echo ""
  printf '%sNothing was installed into /usr/local.%s\n' "$DIM" "$RESET"
  printf '%sOpen the DMG and drag ntfsmac.app to Applications when ready.%s\n' "$DIM" "$RESET"
}

main() {
  cd "$REPO_ROOT" || fail "Could not enter the repository directory."

  if [[ "$#" -gt 2 ]]; then
    usage >&2
    fail "Too many arguments."
  fi

  case "${1:-}" in
    "")
      INTERACTIVE=1
      choose_target
      choose_legacy_mode
      ;;
    cli | gui | both)
      TARGET="$1"
      banner
      info "Selected target: $TARGET"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown target '$1'."
      ;;
  esac

  case "${2:-}" in
    "") ;;
    --no-legacy) LEGACY_ENABLED=0 ;;
    *)
      usage >&2
      fail "Unknown option '${2:-}'."
      ;;
  esac

  check_platform
  prepare_toolchain
  configure_gui_signing
  build_runtime

  case "$TARGET" in
    cli) package_cli ;;
    gui) package_gui ;;
    both)
      package_cli
      package_gui
      ;;
  esac

  print_summary
  pause_if_interactive
}

main "$@"
