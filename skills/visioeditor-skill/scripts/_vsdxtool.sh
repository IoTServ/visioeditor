#!/usr/bin/env bash
# Resolve how to invoke `vsdxtool` for the thin wrappers in this directory.
set -euo pipefail

_skill_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_repo_root="$(cd "$_skill_root/../.." && pwd)"
_vsdx_pkg="$_repo_root/packages/vsdx"

run_vsdxtool() {
  if [[ -n "${VSDXTOOL:-}" ]]; then
    exec "$VSDXTOOL" "$@"
  fi
  if command -v vsdxtool >/dev/null 2>&1; then
    exec vsdxtool "$@"
  fi
  if [[ -x "$_vsdx_pkg/vsdxtool" ]]; then
    exec "$_vsdx_pkg/vsdxtool" "$@"
  fi
  if [[ -f "$_vsdx_pkg/bin/vsdxtool.dart" ]] && command -v dart >/dev/null 2>&1; then
    exec dart run --verbosity=error "$_vsdx_pkg/bin/vsdxtool.dart" "$@"
  fi
  echo "vsdxtool not found. Install the Dart SDK or build:" >&2
  echo "  bash packages/vsdx/tool/build_agent_binaries.sh" >&2
  exit 1
}
