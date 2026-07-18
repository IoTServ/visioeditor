# Live preview & MCP setup

Watch the diagram appear and update **inside the running visioeditor app** as
you build it.

## Enable the bridge in the app

1. Launch the app: `flutter run -d macos` (or the built `visioeditor.app`).
2. Open the More (⋯) menu → check **"Agent live preview"**.
3. The app starts a loopback (127.0.0.1) WebSocket on a random port and writes
   a handshake file to `~/.visioeditor/agent-bridge.json` (`{port, token}`,
   `chmod 600`). It's removed when you turn the toggle off.

Security: loopback-only, random port, one-time token, **off by default**.

## Two ways to preview live

**A. File + auto-reload (works with the CLI alone).** Open a `.vsdx` in the app
(with the bridge on), then every `vsdxtool build`/`patch` that rewrites that
file is auto-reloaded within ~1s (unless you have unsaved edits).

**B. MCP live tools (no disk write, instant).**
- `open_in_app({ path })` — open a file in the app.
- `live_apply_ops({ ops })` — apply Edit Ops to the active doc in memory
  (instant repaint; no file write).
- `snapshot({ page? })` — get a PNG of the current page (for visual self-check).
- `get_app_state()` — pages, selection, dirty flag, shape counts.

Typical live flow: `create_diagram({ spec, open:true })` → a few
`live_apply_ops` to refine → `snapshot` to self-check → tell the user it's ready.

## Register the MCP server (Cursor / Claude)

Build it once: `cd packages/vsdx && dart compile exe bin/vsdxtool_mcp.dart -o vsdxtool-mcp`.

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
`validate`, `explain`, `search_shapes`, `open_in_app`, `live_apply_ops`,
`snapshot`, `get_app_state` are available to the Agent.

## Protocol (for reference)

WebSocket JSON messages `{id, method, params}` → `{id, ok, result}`; the app
also pushes `{event, data}` (`documentChanged`, `fileChangedOnDisk`). Methods:
`ping`, `getState`, `open`, `reload`, `applyOps`, `snapshot` (PNG base64),
`save`. Connect to `ws://127.0.0.1:<port>/?token=<token>` from the handshake
file. The `BridgeClient` in `package:vsdx/agent.dart` implements this.
