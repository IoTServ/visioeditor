#!/usr/bin/env bash
# Validate a .vsdx file.
# Usage: scripts/validate.sh -i diagram.vsdx
set -euo pipefail
# shellcheck source=_vsdxtool.sh
source "$(dirname "$0")/_vsdxtool.sh"
run_vsdxtool validate "$@"
