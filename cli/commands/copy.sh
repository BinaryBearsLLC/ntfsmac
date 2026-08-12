#!/bin/bash
set -u
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=../lib/verified-copy.sh
source "$SCRIPT_DIR/../lib/verified-copy.sh"
verified_copy_copy_main "$@"
