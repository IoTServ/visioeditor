# Troubleshooting

## `vsdxtool` not found / won't run

- Resolve the command: try `vsdxtool version`; else
  `cd packages/vsdx && dart run bin/vsdxtool.dart version`.
- Build a binary: `cd packages/vsdx && dart compile exe bin/vsdxtool.dart -o vsdxtool`.
- Needs the Dart SDK (`dart --version`). It's bundled with Flutter.

## Build/patch says the spec is invalid

- The Spec must be valid JSON. `nodes[].id` is required and edge `from`/`to`
  must match node ids. See `references/spec-schema.md`.
- Reading from stdin: `... | vsdxtool build -o out.vsdx` (no `-s`).

## `validate` reports warnings

- **off-page**: a shape's coordinates are outside the page — usually a bad
  hand-set `x`/`y`. Remove coords to auto-layout, or `move_shape` onto the page.
- **overlap**: nodes too close — raise `layout.spacing` and rebuild, or
  `move_shape`. Warnings don't block; `--strict` makes them fail.
- **duplicate id / dangling connector**: only from hand-edited files; rebuild
  or fix the offending op.

## Live preview: MCP live tools fail to connect

- Error "Agent live preview is not running": open the app and enable **More ⋯
  → Agent live preview**. Confirm a handshake exists at
  `~/.visioeditor/agent-bridge.json` or (sandboxed macOS)
  `~/Library/Containers/cloud.iothub.visioeditor.visioeditor/Data/.visioeditor/agent-bridge.json`
  (Debug builds use the `.debug` bundle id).
- One app instance owns the bridge at a time; the handshake file holds the
  current port + token. Toggle off/on to refresh it.
- The bridge is loopback-only; run the Agent/MCP on the **same machine**.

## Auto-reload didn't pick up my file change

- The watched file is the **active tab's** document. Make sure that tab holds
  the file you're editing, and that it has no unsaved edits (dirty docs aren't
  auto-reloaded — a `fileChangedOnDisk` event is emitted instead). Use the
  `reload` method / re-open to force it.

## Rendered SVG/preview looks wrong

- Re-run `validate`; fix overlaps/off-page first.
- For layout-wide issues, regenerate the spec (change `direction`/`spacing`)
  rather than nudging individual shapes.
- Connectors crossing shapes: auto-layout routes around obstacles on rebuild;
  for hand-placed diagrams, `move_shape` the obstacle.

## PNG for self-check

- Headless SVG: `vsdxtool render -i file.vsdx -o file.svg`.
- PNG requires the app: use the MCP `snapshot` tool (bridge enabled), or the
  editor's Export menu.
