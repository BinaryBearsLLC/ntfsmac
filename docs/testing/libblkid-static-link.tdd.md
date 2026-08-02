# TDD Evidence: static-link libblkid into anylinuxfs (tosbaha #1 fix)

**Source plan:** conversational `/ecc:plan` output, then a user-driven pivot. Original plan
was Option C (build static libblkid from a pinned vanilla util-linux source). **The
maintainer rejected the vanilla from-source build** ("we already surely know homebrew
version works for this… don't try to add a different one") and directed the fix to consume
Homebrew's already-built static archives instead. No `*.plan.md` file; journeys derived
during this run.

## User journey

As a user on a Mac without `brew install util-linux`, I want `ntfsmac` and the GUI app to
launch and mount without a DYLD `libblkid.1.dylib` abort, so the install actually works.

## Task report

| Plan task | Execution summary | Validation command | Result |
|---|---|---|---|
| Record build dep | `UTIL_LINUX_BREW_FORMULA=util-linux` in `build/sources.lock` (no tarball/sha256 — Homebrew install consumed, not fetched) | `bats tests/build/lock.bats` | PASS — "every required pin key is present" |
| `build-libblkid-static.sh` (stager) | Resolves Homebrew `util-linux`+`gettext`, copies ONLY `libblkid.a`+`libuuid.a`+`libintl.a`+headers into a dylib-free stage, authors `blkid.pc`/`uuid.pc`/`intl.pc` | `bats tests/build/util-linux.bats` | PASS — 4/4 (stager run for real; dylib-free; `.pc` chain; pkg-config resolves) |
| Wire into `build-all.sh` | Calls the stager before `build_anylinuxfs`; exports `PKG_CONFIG_PATH`+`PKG_CONFIG_ALL_STATIC=1`; neutralizes the homebrew path in the CACHE_DIR `.cargo/config.toml` | `bats tests/build/build-all.bats --filter "wires static libblkid"` | RED → GREEN |
| `preflight.sh` | Added `brew` + `pkg-config` checks + `check_util_linux_static` asserting `libblkid.a`/`libuuid.a`/`libintl.a` present | `bats tests/build/preflight.bats` (missing-tool isolation) | PASS (real-PATH test fails only on missing `go` in this sandbox, pre-existing) |
| `AUDIT.md` | Recorded the Homebrew staging decision, transitive-dep chain, and rejected alternatives | — | appended |
| CI workflows | Added `gettext pkg-config` to the `brew install` lines in `ci.yml` (×2) and `package-dmg.yml` | — | appended |
| Static-link proof | Tiny C program linked via `pkg-config --static --libs blkid` against the staged `.a` archives | `cc $(pkg-config --static --cflags --libs blkid) probe.c` + `otool -L` | PASS — builds, runs, no Homebrew dylib in `otool -L` |

## Test specification

| # | What is guaranteed | Test file / command | Type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | `build-all.sh` wires static libblkid linking (`PKG_CONFIG_ALL_STATIC=1` present; no active `PKG_CONFIG_PATH` assignment points at homebrew util-linux) | `tests/build/build-all.bats: "wires static libblkid linking"` | unit (grep) | PASS | `ok 15` |
| 2 | Built `vendor/bin/anylinuxfs` has no `libblkid` entry in `otool -L` (no runtime dylib → no DYLD abort on machines without `brew install util-linux`) | `tests/build/build-all.bats: "does not dynamically link libblkid"` | integration (real build) | PASS | full `build-all.sh` run on this macOS VM; `otool -L` shows only system frameworks/libs (oncrpc, Hypervisor, SystemConfiguration, Security, DiskArbitration, CoreFoundation, libSystem, libobjc, Foundation, libiconv, CoreServices) — no `libblkid`/`libuuid`/`libintl`/homebrew dylib |
| 3 | `build-libblkid-static.sh` exists and is executable | `tests/build/util-linux.bats` | unit | PASS | `ok 1` |
| 4 | Stager produces a dylib-free stage with `libblkid.a`+`libuuid.a`+`.pc` (no `.dylib` can leak in) | `tests/build/util-linux.bats` | unit (real stager run) | PASS | `ok 2` |
| 5 | Staged `blkid.pc` pulls libuuid statically (`Requires.private: uuid`) and points at the stage, not Homebrew | `tests/build/util-linux.bats` | unit | PASS | `ok 3` |
| 6 | `pkg-config --static --libs blkid` resolves to the staged static archives (`-lblkid`+`-luuid`+stage libdir) | `tests/build/util-linux.bats` | unit | PASS | `ok 4` |
| 7 | `UTIL_LINUX_BREW_FORMULA` pin key is present in `sources.lock` | `tests/build/lock.bats: "every required pin key is present"` | unit | PASS | `ok 6` |
| 8 | preflight fails when a required tool (incl. `brew`/`pkg-config`) is missing | `tests/build/preflight.bats: "fails when a required tool is missing"` | unit | PASS | `ok 10` |
| 9 | A real C program links against the staged static archives via pkg-config and runs (`blkid_get_cache` succeeds); `otool -L` shows only system libs (libSystem, libiconv, CoreFoundation) — no `libblkid`/`libuuid`/`libintl` dylib | manual proof (this session) | integration | PASS | see below |

## Static-link proof (this session, real)

```
$ STAGE=/tmp/ntfsmac-lblkid-proof ./build/build-libblkid-static.sh
$ cc $(PKG_CONFIG_PATH=$STAGE/lib/pkgconfig pkg-config --static --cflags --libs blkid) probe.c -o probe
   → builds clean (exit 0)
$ otool -L probe
    /usr/lib/libSystem.B.dylib
    /usr/lib/libiconv.2.dylib
    /System/Library/Frameworks/CoreFoundation.framework/.../CoreFoundation
   → NO libblkid / libuuid / libintl dylib
$ ./probe
    blkid ok
```

This is the mechanism the real `cargo build` uses (libblkid-rs-sys → pkg-config → the staged
`.pc`). The only runtime dylibs added are OS-provided (libSystem, libiconv, CoreFoundation —
present on every macOS); **no Homebrew dylib is needed at runtime.**

## RED → GREEN evidence

- **RED (test 1, wiring):** before the fix, `bats tests/build/build-all.bats --filter "wires static libblkid"` → `not ok` — `PKG_CONFIG_ALL_STATIC=1` absent from `build-all.sh`. Failure caused by the intended missing implementation, not setup/syntax.
- **GREEN (test 1, wiring):** after adding the env exports + `.cargo/config.toml` neutralization, same command → `ok`. (One intermediate failure: the first assertion form matched the homebrew path in an explanatory *comment*; fixed the test to check only non-comment active assignments — same comment-tolerance the existing freebsd test uses.)
- **RED→GREEN (tests 3–6, stager):** rewritten from the deleted vanilla-fetch tests to the Homebrew stager. Initial run: tests 3–4 failed on test-assertion bugs (the `.pc` uses `libdir=${prefix}/lib`, so `^libdir=` doesn't contain the literal stage path; and test 4 forgot to set `PKG_CONFIG_PATH`). Fixed the assertions → all 4 PASS.
- **Static-link proof RED→GREEN:** the proof C program went RED three times on real transitive deps the vanilla plan never surfaced — `_libintl_gettext` (→ stage `libintl.a` + `intl.pc`), then `_CFArrayGetCount` (→ `-framework CoreFoundation` in `intl.pc` Libs.private), then `_iconv` (→ `-liconv`, system `libiconv.2.dylib`). Each was a real undefined-symbol linker error, fixed by extending the staged `.pc` chain. GREEN = clean build + run + `otool -L` showing only system libs.
- **RED/GREEN (test 2, linkage):** the real acceptance guard. RED by construction on the current dynamic-link build; GREEN after the full `build-all.sh` run on this macOS VM — `vendor/bin/anylinuxfs` built and `otool -L` shows no `libblkid` dylib. **Run here, not just on the build machine.**

## Coverage and known gaps

- Fast (non-build) tests: all PASS (`util-linux.bats` 4/4, `lock.bats` 6/6, `preflight.bats` isolated tests PASS, `build-all.bats` wiring + linkage PASS — 17/17 in the filtered fast subset).
- **Full build: GREEN on this macOS VM.** `./build/build-all.sh` exit 0 — "build-all: done". `vendor/bin/anylinuxfs` built (Mach-O arm64), ad-hoc signed with entitlements via `sign.sh`. `otool -L` confirms no `libblkid`/`libuuid`/`libintl`/homebrew dylib (test 2 PASS). cargo test GREEN for all three crates: common-utils 8 passed, anylinuxfs 41 passed, vmproxy 8 passed.
- `run_tests` gap found and fixed during the real run: the debug test build of anylinuxfs re-runs libblkid-rs-sys's build script, which needs the SAME `PKG_CONFIG_PATH`+`PKG_CONFIG_ALL_STATIC` env as `build_anylinuxfs`. Without it the test build fails with "Package blkid not found" (the neutralized `.cargo/config.toml` removed the homebrew fallback deliberately). Fix: `run_tests` now exports that env around the anylinuxfs `cargo test`. Verified GREEN (41 passed).
- The "Failed to run VM: start vm error: Invalid argument (errno 22)" line during `init-rootfs` is the vmproxy-embed step trying to boot the microVM — fails in this sandbox (no real hypervisor), non-fatal, build still exits 0. Expected on a real Apple Silicon Mac to succeed (Hypervisor.framework is present).
- **Risk closed by the pivot:** the vanilla from-source build risk (configure/make failing on macOS arm64, byte-difference from Homebrew) is eliminated — we consume Homebrew's known-good static archives directly. The full anylinuxfs cargo build picks up the staged `.pc` correctly (proven by the GREEN release build + test 2).

## Merge evidence

If the checkpoint commits are squashed, copy the RED/GREEN summary above into the PR body so
reviewers can answer what was verified and how. Checkpoint commits (path 1 — user creates):
1. `test: add wiring guard + stager acceptance for libblkid static-link (tosbaha #1)` — RED
2. `fix: static-link libblkid from Homebrew static archives (tosbaha #1)` — GREEN (fast tests + standalone proof)
3. `docs: record Homebrew static-libblkid staging in AUDIT.md + CI` — evidence