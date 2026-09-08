---
name: Compatibility report
about: Share a successful test or a compatibility limitation on an Apple Silicon Mac
title: "[Compatibility] macOS version / chip family"
assignees: ''
---

## Environment

- ntfsmac version and build (Settings):
- macOS version and build:
- Chip family (for example M1 or M5; no serial number):
- Native Mac or virtual machine:
- Install source:
- Filesystem and driver (NTFS / ntfs-3g, experimental NTFS3, or ext2/3/4):

## Operations completed

Describe what you actually tested and whether each step succeeded:

- App and helper setup:
- Drive detection, including other connected filesystems if relevant:
- Mount:
- Copy and read back:
- Unmount, reconnect/remount and read back:
- Any hash verification, errors or limitations:

Successful reports are welcome. Use only backed-up or disposable test data; no formatting,
unplug-during-write or corruption testing is required. A reported result covers the stated
system and operations, not every Mac with the same chip.

## Diagnostic attachment

Hold Command (⌘) while clicking **Diagnose** to save JSON. Review it before attaching it here;
ntfsmac does not upload it automatically. Do not include personal files, serials, volume names,
credentials or unrelated logs. If the export is unavailable, describe that instead.

Community reports are recorded separately from maintainer qualification. For suspected security
vulnerabilities, use the private reporting instructions in `SECURITY.md`, not this public form.
