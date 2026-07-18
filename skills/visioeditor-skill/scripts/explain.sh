#!/usr/bin/env bash
# Explain a .vsdx as structured Markdown.
# Usage: scripts/explain.sh -i diagram.vsdx
set -euo pipefail
# shellcheck source=_vsdxtool.sh
source "$(dirname "$0")/_vsdxtool.sh"
run_vsdxtool explain "$@"
