/// Agent-facing surface of `package:vsdx` — the pure-Dart building blocks the
/// headless CLI (`bin/vsdxtool.dart`), the MCP server, and the app live-preview
/// bridge all share to turn a **Diagram Spec** / **Edit Ops** JSON into a
/// round-trip-faithful `.vsdx`.
///
/// Everything here is Flutter-free and builds on the existing engine
/// (`VsdxShapeFactory` / `VsdxWriter` / `DocumentParser` / `ObstacleRouter`),
/// so a diagram authored by an Agent renders identically to one drawn by hand
/// in the editor. See `docs/MCP_SKILL_PLAN.md`.
library;

export 'src/agent/bridge_client.dart';
export 'src/agent/diagram_spec.dart';
export 'src/agent/edit_ops.dart';
export 'src/agent/inspect.dart';
export 'src/agent/mcp_server.dart';
export 'src/agent/mermaid_import.dart';
export 'src/agent/mcp_tools.dart';
export 'src/agent/stencil_catalog.dart';
