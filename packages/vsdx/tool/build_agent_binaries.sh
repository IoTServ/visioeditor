#!/usr/bin/env bash
# Compile the Agent backend to single-file native binaries (fast startup, no
# Dart SDK needed at run time). Run from anywhere:
#
#   bash packages/vsdx/tool/build_agent_binaries.sh
#
# Produces, next to this package:
#   packages/vsdx/vsdxtool       — the headless CLI
#   packages/vsdx/vsdxtool-mcp   — the MCP (stdio) server
#
# To use the compiled MCP server in Cursor/Claude, point the config at the
# absolute path of vsdxtool-mcp instead of `dart run …` (see
# skills/visioeditor-skill/references/live-preview.md).
set -euo pipefail

cd "$(dirname "$0")/.."   # -> packages/vsdx

echo "==> dart pub get"
dart pub get >/dev/null

echo "==> compiling vsdxtool"
dart compile exe bin/vsdxtool.dart -o vsdxtool

echo "==> compiling vsdxtool-mcp"
dart compile exe bin/vsdxtool_mcp.dart -o vsdxtool-mcp

echo "Done:"
echo "  $(pwd)/vsdxtool"
echo "  $(pwd)/vsdxtool-mcp"
