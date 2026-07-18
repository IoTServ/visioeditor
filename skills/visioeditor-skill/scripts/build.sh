#!/usr/bin/env bash
# Build a .vsdx from a Diagram Spec JSON.
# Usage: scripts/build.sh -o out.vsdx [-s spec.json] [--style corporate]
set -euo pipefail
# shellcheck source=_vsdxtool.sh
source "$(dirname "$0")/_vsdxtool.sh"
run_vsdxtool build "$@"
