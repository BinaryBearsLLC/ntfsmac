#!/bin/bash
# build/build-libblkid-static.sh — stage Homebrew's static libblkid.a (+ libuuid.a) so
# anylinuxfs links libblkid statically instead of dynamically loading
# /opt/homebrew/*/libblkid.1.dylib (tosbaha #1: DYLD abort on machines without
# `brew install util-linux` at RUNTIME).
#
# Why Homebrew's archives and not a from-source build: util-linux is already a confirmed
# build-toolchain dep (build-all.sh/preflight.sh require it), Homebrew's util-linux ships
# BOTH libblkid.a and libblkid.1.dylib, and Homebrew's build is the one known to compile
# clean on macOS (a vanilla util-linux tarball build is the risky path we deliberately do
# NOT take). We static-link so the shipped anylinuxfs binary has no libblkid dylib in its
# otool -L output — the user never needs `brew install util-linux` to run ntfsmac.
#
# What this script does NOT do: build anything from source, fetch a tarball, or apply
# patches. It copies Homebrew's already-built static archives + headers into a stage dir
# that contains ONLY the .a archives (no .dylib), and authors blkid.pc/uuid.pc pointing at
# that dir. With only .a present, `-lblkid`/`-luuid` resolve to the static archives for
# certain — no reliance on linker static-preference flags. build-all.sh points
# PKG_CONFIG_PATH at this stage + sets PKG_CONFIG_ALL_STATIC=1 (belt-and-suspenders).
#
# libblkid depends on libuuid, so both archives are staged and blkid.pc carries
# Requires.private: uuid (PKG_CONFIG_ALL_STATIC=1 pulls uuid's static archive in
# transitively). libuuid needs -lpthread (its Libs.private), provided by libSystem.
#
# libblkid also references GNU gettext (_libintl_gettext) — found by the static-link
# proof, not guessed: Homebrew's util-linux was built against gettext, and libSystem
# does NOT provide libintl (it's a GNU lib, not Apple's). So we stage Homebrew
# gettext's libintl.a too and add `intl` to blkid.pc's Requires.private. Without this
# the static link fails with "Undefined symbols: _libintl_gettext".
#
# libintl.a itself drags in two more transitive deps (also found by the proof, not
# guessed): iconv (_iconv/_iconv_open) and CoreFoundation (_CFArrayGetCount, used for
# language-preference lookup). Both are OS-provided and present on every macOS —
# libiconv.2.dylib lives in /usr/lib and CoreFoundation is a system framework — so
# they add NO Homebrew runtime dependency (the tosbaha #1 goal: no Homebrew dylib
# needed at runtime). intl.pc declares them in Libs.private so `pkg-config --static`
# pulls them. libintl.a is a static archive, so it adds no runtime dylib either.
set -uo pipefail

# Default to a SPACE-FREE path under TMPDIR, not the repo — same reason build-all.sh
# copies anylinuxfs to a space-free CACHE_DIR: this repo's path-with-spaces makes
# pkg-config backslash-escape the -I/-L paths, which the pkg-config Rust crate (and
# cc-rs) mis-parse. A space-free stage keeps the .pc paths clean.
STAGE="${NTFSMAC_LIBBLKID_STAGE:-${TMPDIR:-/tmp}/ntfsmac-build/libblkid-static}"

# Resolve Homebrew's util-linux install. `brew --prefix util-linux` returns the opt symlink
# (/opt/homebrew/opt/util-linux) on Apple Silicon Homebrew; it's stable across bottle
# version bumps (the Cellar path behind it changes per version, the opt symlink does not).
resolve_brew_prefix() {
  local prefix
  if ! command -v brew >/dev/null 2>&1; then
    echo "build-libblkid-static: HARD-STOP — brew not found (util-linux is a build dep, install Homebrew)" >&2
    return 1
  fi
  prefix="$(brew --prefix util-linux 2>/dev/null)" || true
  if [[ -z "$prefix" || ! -d "$prefix" ]]; then
    echo "build-libblkid-static: HARD-STOP — util-linux not installed via Homebrew (run: brew install util-linux)" >&2
    return 1
  fi
  printf '%s\n' "$prefix"
}

main() {
  local brew_prefix
  brew_prefix="$(resolve_brew_prefix)" || exit 1

  local blkid_a="$brew_prefix/lib/libblkid.a"
  local uuid_a="$brew_prefix/lib/libuuid.a"
  if [[ ! -f "$blkid_a" ]]; then
    echo "build-libblkid-static: HARD-STOP — $blkid_a missing (Homebrew util-linux build without static archives; file a build issue)" >&2
    exit 1
  fi
  if [[ ! -f "$uuid_a" ]]; then
    echo "build-libblkid-static: HARD-STOP — $uuid_a missing (libblkid depends on libuuid; check Homebrew util-linux install)" >&2
    exit 1
  fi

  # GNU gettext — libblkid.a references _libintl_gettext (see header comment). Homebrew
  # gettext ships libintl.a; resolve it the same way as util-linux (opt symlink is stable).
  local gettext_prefix
  gettext_prefix="$(brew --prefix gettext 2>/dev/null)" || true
  if [[ -z "$gettext_prefix" || ! -d "$gettext_prefix" ]]; then
    echo "build-libblkid-static: HARD-STOP — gettext not installed via Homebrew (libblkid needs libintl; run: brew install gettext)" >&2
    exit 1
  fi
  local intl_a="$gettext_prefix/lib/libintl.a"
  if [[ ! -f "$intl_a" ]]; then
    echo "build-libblkid-static: HARD-STOP — $intl_a missing (Homebrew gettext build without static archive; file a build issue)" >&2
    exit 1
  fi

  # Clean stage so a stale dylib can never linger from a prior experiment.
  rm -rf "$STAGE"
  mkdir -p "$STAGE/lib/pkgconfig" "$STAGE/include"

  # Copy ONLY the static archives (never the dylibs) — this is what forces -lblkid to
  # resolve to the .a. Headers go alongside so the .pc Cflags -I resolves inside the stage.
  cp "$blkid_a" "$STAGE/lib/libblkid.a"
  cp "$uuid_a"  "$STAGE/lib/libuuid.a"
  cp "$intl_a"  "$STAGE/lib/libintl.a"
  cp -R "$brew_prefix/include/blkid" "$STAGE/include/blkid"
  cp -R "$brew_prefix/include/uuid"  "$STAGE/include/uuid"
  # libintl.h lives in gettext's include root (not a subdir).
  cp "$gettext_prefix/include/libintl.h" "$STAGE/include/libintl.h" 2>/dev/null || true

  # Read the version from Homebrew's own blkid.pc so our staged .pc reports the real version
  # (cosmetic — pkg-config uses it only for display/min-version checks, none of which we do).
  local version="unknown"
  local brew_pc="$brew_prefix/lib/pkgconfig/blkid.pc"
  if [[ -f "$brew_pc" ]]; then
    version="$(awk -F': ' '/^Version:/ {print $2; exit}' "$brew_pc")"
  fi

  # Author our own .pc files pointing at the stage. blkid Requires.private uuid so static
  # linking pulls libuuid in; uuid carries -lpthread in Libs.private (libSystem provides it).
  cat > "$STAGE/lib/pkgconfig/blkid.pc" <<EOF
prefix=$STAGE
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: blkid
Description: util-linux blkid (static archive staged by ntfsmac)
Version: $version
Requires.private: uuid intl
Cflags: -I\${includedir}/blkid
Libs: -L\${libdir} -lblkid
EOF

  cat > "$STAGE/lib/pkgconfig/intl.pc" <<EOF
prefix=$STAGE
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: intl
Description: GNU gettext libintl (static archive staged by ntfsmac)
Version: $version
Cflags: -I\${includedir}
Libs: -L\${libdir} -lintl
Libs.private: -liconv -framework CoreFoundation
EOF

  cat > "$STAGE/lib/pkgconfig/uuid.pc" <<EOF
prefix=$STAGE
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: uuid
Description: util-linux uuid (static archive staged by ntfsmac)
Version: $version
Cflags: -I\${includedir}/uuid
Libs: -L\${libdir} -luuid
Libs.private: -lpthread
EOF

  # Sanity: no dylib leaked into the stage (the whole point — only .a here).
  if [[ -n "$(find "$STAGE/lib" -name '*.dylib' 2>/dev/null | head -1)" ]]; then
    echo "build-libblkid-static: HARD-STOP — a .dylib leaked into the stage; refusing to enable" >&2
    exit 1
  fi

  echo "build-libblkid-static: staged Homebrew static libblkid.a + libuuid.a → $STAGE/lib"
  echo "build-libblkid-static: pkg-config dir — $STAGE/lib/pkgconfig"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi