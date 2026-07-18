#!/usr/bin/env bash
# Render a .vsdx to SVG (or other formats supported by vsdxtool render).
# Usage: scripts/render.sh -i diagram.vsdx -o diagram.svg
set -euo pipefail
# shellcheck source=_vsdxtool.sh
source "$(dirname "$0")/_vsdxtool.sh"
run_vsdxtool render "$@"
