/// `vsdxtool-mcp` — a Model Context Protocol server exposing the visioeditor
/// Agent toolset over stdio.
///
/// **File tools** (work without the app): `create_diagram`, `apply_ops`,
/// `export`, `validate`, `explain`, `search_shapes`.
/// **Live tools** (drive the running editor via the bridge): `open_in_app`,
/// `live_apply_ops`, `snapshot`, `get_app_state`.
///
/// Register in Cursor / Claude (see `skills/visioeditor-skill/references/`):
///   { "command": "dart", "args": ["run", "vsdx:vsdxtool_mcp"] }
/// or compile: `dart compile exe bin/vsdxtool_mcp.dart -o vsdxtool-mcp`.
///
/// See `docs/MCP_SKILL_PLAN.md` (M3).
library;

import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

Future<void> main(List<String> args) async {
  final server = McpServer(name: 'visioeditor', version: kVsdxEngineVersion);
  registerVsdxMcpTools(server);
  await server.serve();
}
