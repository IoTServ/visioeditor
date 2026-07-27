# Live preview & MCP setup

Watch the diagram appear and update **inside the running visioeditor app** as
you build it.

## Enable the bridge in the app

1. Launch the app: `flutter run -d macos` (or the built `visioeditor.app`).
2. Open the More (⋯) menu → check **"Agent live preview"**.
3. The app starts a loopback (127.0.0.1) WebSocket on a random port and writes
   a handshake file to `~/.visioeditor/agent-bridge.json` (or, on sandboxed
   macOS, under
   `~/Library/Containers/<bundle-id>/Data/.visioeditor/agent-bridge.json`).
   Clients probe both locations. The file is `chmod 600` and removed when you
   turn the toggle off.

Security: loopback-only, random port, one-time token, **off by default**.

## Two ways to preview live

**A. File + auto-reload (works with the CLI alone).** Open a `.vsdx` in the app
(with the bridge on), then every `vsdxtool build`/`patch` that rewrites that
file is auto-reloaded within ~1s (unless you have unsaved edits).

**B. MCP live tools (no disk write, instant).**
- `open_in_app({ path })` — open a file in the app.
- `live_apply_ops({ ops })` — apply Edit Ops to the active doc in memory
  (instant repaint; no file write).
- `list_pages()` / `select_page({ page })` — inspect page setup and switch the
  visible page tab.
- `list_layers({ page? })` / `select_layer({ layerId, page? })` — inspect layer
  flags/membership and select every visible, editable object on a layer.
- `list_shapes({ page? })` / `select({ ids })` — discover/highlight shapes and
  inspect Shape Data/hyperlinks, editable fixed connection points, and
  connector route, rounded corners, endpoints, glue targets, and bend points.
- `snapshot({ page? })` — get a PNG of the current page (for visual self-check).
- `get_app_state()` — pages, selection, dirty flag, shape counts.

Typical live flow: `create_diagram({ spec, open:true })` → a few
`live_apply_ops` to refine → `snapshot` to self-check → tell the user it's ready.

## Register the MCP server (Cursor / Claude)

**This repo ships a ready `.cursor/mcp.json`** that launches the server with
`dart run packages/vsdx/bin/vsdxtool_mcp.dart` (no compile step) — open the repo
in Cursor and the `visioeditor` MCP tools are available. To use it elsewhere,
or to prefer a fast native binary, build once
(`bash packages/vsdx/tool/build_agent_binaries.sh` →
`packages/vsdx/vsdxtool-mcp`) and register one of the configs below.

**Cursor** — `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global):

```json
{
  "mcpServers": {
    "visioeditor": {
      "command": "/absolute/path/to/packages/vsdx/vsdxtool-mcp"
    }
  }
}
```

Or run from source without compiling:

```json
{
  "mcpServers": {
    "visioeditor": {
      "command": "dart",
      "args": ["run", "bin/vsdxtool_mcp.dart"],
      "cwd": "/absolute/path/to/packages/vsdx"
    }
  }
}
```

**Claude Desktop** — `claude_desktop_config.json` uses the same `mcpServers`
shape.

After registering, the tools `create_diagram`, `apply_ops`, `export`,
`validate`, `explain`, `list_pages`, `list_layers`, `list_shapes`,
`search_shapes`, `open_in_app`, `live_apply_ops`, `select_page`,
`select_layer`, `select`, `snapshot`, `get_app_state`, plus page, layer, and
shape convenience edits (including `set_shape_data` / `set_shape_links` and
`set_connection_points`, `set_connector`, and `reconnect_connector`) are
available to the Agent. `list_shapes` exposes nested `parentId` values, and
`reparent_shapes` can move shapes into a draw.io-style container/group or
eject them with `parent: "none"`. It also reports container fold state;
`set_container_collapsed` collapses or expands a container live and clears
selections that become hidden.

## Protocol (for reference)

WebSocket JSON messages `{id, method, params}` → `{id, ok, result}`; the app
also pushes `{event, data}` (`documentChanged`, `fileChangedOnDisk`). Methods:
`ping`, `getState`, `listShapes`, `listLayers`, `selectPage`, `selectLayer`,
`select`, `open`, `reload`, `applyOps`, `snapshot` (PNG base64), `save`.
Connect to `ws://127.0.0.1:<port>/?token=<token>` from the handshake file.
The `BridgeClient` in `package:vsdx/agent.dart` implements this.
