#!/usr/bin/env bash
# Apply Edit Ops JSON to a .vsdx.
# Usage: scripts/patch.sh -i diagram.vsdx --ops ops.json
set -euo pipefail
# shellcheck source=_vsdxtool.sh
source "$(dirname "$0")/_vsdxtool.sh"
run_vsdxtool patch "$@"
