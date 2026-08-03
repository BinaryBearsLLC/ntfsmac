#!/bin/bash
# Canonical product/build versions shared by the installed CLI diagnostics and the GUI bundle.
# build/package-app.sh verifies these values against both embedded Info.plists before packaging,
# so a release cannot silently report different versions in Settings, Diagnose, and JSON.

# This file is intentionally sourced by other scripts; its assignments are its public API.
# shellcheck disable=SC2034

NTFSMAC_VERSION="1.0"
NTFSMAC_BUILD_VERSION="1"
NTFSMAC_DIAGNOSTIC_SCHEMA_VERSION="2"
