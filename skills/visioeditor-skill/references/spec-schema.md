# Diagram Spec & Edit Ops — schema (v0)

Both are plain JSON. The engine maps them onto `VsdxShapeFactory` (build) and
the round-trip `VsdxWriter` (edit), so output re-opens losslessly in Visio.

Units are **inches**. The page origin is **bottom-left** (Visio convention):
larger `y` is higher on the page.

---

## Diagram Spec (build)

```jsonc
{
  "version": 0,                       // optional
  "title": "My Diagram",              // optional; page name + docProps title
  "layout": {
    "direction": "TB",               // "TB" (top→bottom) | "LR" (left→right)
    "spacing": 0.6                    // inches between nodes/layers
  },
  "page": {                           // optional; auto-sized to fit if omitted
    "size": "letter",                // letter|legal|tabloid|a3|a4|a5
    "landscape": false,
    "width": 11.0,                   // overrides size (inches)
    "height": 8.5,
    "background": "#ffffff"
  },
  "nodes": [
    {
      "id": "gw",                    // required; referenced by edges
      "stencil": "process",          // see shape-catalog.md (default: rectangle)
      "text": "API Gateway",         // label (\n for line breaks)
      "x": 2.0, "y": 3.0,            // optional CENTER (inches); omit to auto-layout
      "w": 1.7, "h": 0.9,            // optional size (inches)
      "fill": "#DAE8FC",            // #RGB / #RRGGBB / #AARRGGBB / "none"
      "line": "#6C8EBF",            // stroke color / "none"
      "textColor": "#1F2937",
      "bold": false
    }
  ],
  "edges": [
    {
      "from": "gw",                  // node id
      "to": "db",                    // node id
      "label": "SQL",                // optional edge label
      "arrow": true,                 // false | "none" -> no end arrowhead
      "line": "#333333"             // optional stroke color
    }
  ]
}
```

### Rules & behavior

- **Auto-layout**: if *any* node omits `x`/`y`, a layered layout places **all**
  nodes (longest-path layering from edges; `direction` controls the flow axis)
  and the page is sized to fit. If every node has `x`/`y`, they're used as-is.
- **Defaults**: node `w`=1.7, `h`=0.9; fill `#DAE8FC`, line `#6C8EBF`, text
  `#1F2937`. Edges get an end arrowhead and glue to both shapes (they re-route
  around shape outlines automatically).
- **Aliases** (accepted): `shape`→`stencil`, `label`→`text`, `width`/`height`→
  `w`/`h`, `stroke`→`line`, `source`/`target`→`from`/`to`, `fontColor`→`textColor`.

### CLI / MCP

```bash
vsdxtool build -s spec.json -o out.vsdx        # or: build - (stdin) 
```
MCP: `create_diagram({ "spec": {…}, "path": "out.vsdx", "open": true })`
(`spec` may be an object or a JSON string; `open` also opens it live in the app).

---

## Edit Ops (edit an existing .vsdx)

```jsonc
{ "ops": [
  { "op": "add_page",      "name": "Review", "width": 11, "height": 8.5 },
  { "op": "add_layer",     "name": "Infrastructure", "active": true,
    "color": "#336699", "ids": [8, 12] },
  { "op": "assign_layer",  "ids": [15], "layerId": 0, "mode": "add" },
  { "op": "set_layer",      "layerId": 0, "visible": true, "locked": false },
  { "op": "add_shape",     "stencil": "decision", "text": "Approved?",
    "x": 4, "y": 5, "w": 1.4, "h": 1, "fill": "#FFF2CC", "bold": true },
  { "op": "add_connector", "from": "shape:12", "to": "shape:8",
    "label": "yes", "arrow": true, "line": "#333333" },
  { "op": "set_style",     "ids": ["shape:12", "shape:8"],
    "fill": "#D5E8D4", "line": "#82B366" },
  { "op": "set_text",      "id": 8, "text": "Ship order", "bold": false },
  { "op": "move_shape",    "id": 8, "x": 6.0, "y": 5.0 },
  { "op": "resize_shape",  "id": 8, "w": 2.0, "h": 1.0 },
  { "op": "duplicate_shape", "ids": [8, 12], "dx": 0.25, "dy": -0.25 },
  { "op": "group",         "ids": [8, 12], "name": "Approval" },
  { "op": "ungroup",       "id": 20 },
  { "op": "z_order",       "id": 8, "action": "front" },
  { "op": "align",         "ids": [8, 12], "mode": "middle" },
  { "op": "distribute",    "ids": [8, 12, 15], "axis": "horizontal" },
  { "op": "delete_shape",  "id": 3 }
] }
```

- **Pages**: `add_page` inserts after the current context by default;
  `duplicate_page` copies a page with a fresh stable page id; `rename_page`,
  `delete_page`, and `set_page` accept optional `index`; `move_page` accepts
  `from` / `to`. `set_page` supports `width`, `height`, `landscape`,
  `background` (`#RRGGBB` or `"none"`), `isBackground`, and
  `backgroundPageId` (stable id from `list_pages`, or `"none"`).
- **Batch page context**: successful page ops switch the context for later ops
  in the same batch. Thus `add_page` followed by `add_shape` creates the shape
  on the new page. `delete_page` always keeps at least one page; page moves
  preserve the active page by stable id.
- **Layers**: `add_layer` creates a stable per-page layer id and can assign
  `ids` immediately. `set_layer` updates `name`, `visible`, `locked`, `print`,
  `active`, `snap`, `glue`, `color`, and color transparency. `assign_layer`
  accepts `replace`, `add`, `remove`, or `clear`; `delete_layer` removes the
  membership recursively without deleting shapes. New shapes and connectors
  automatically join the active layer unless an explicit `layerId` is given.
  Making one layer active deactivates the previous active layer.
- **Shape references**: `"shape:<id>"`, a bare integer, or a numeric string —
  all resolve to the Visio shape id. `from`/`to` for connectors must reference
  existing shapes.
- **Duplicate**: accepts `id` or `ids`; allocates fresh ids for every
  descendant, rewrites internal `Sheet.n!` formulas and connector glue, and
  defaults to draw.io's `dx=0.25`, `dy=-0.25` inch offset.
- **Group / ungroup**: grouping requires at least two editable top-level
  shapes. Ungroup only unwraps ordinary groups; tables, charts, and swimlanes
  retain their structure.
- **Arrange**: `z_order.action` is `front`, `forward`, `backward`, or `back`.
  `align.mode` is `left`, `right`, `center`, `top`, `bottom`, or `middle`;
  a single shape aligns to the page. `distribute.axis` is `horizontal` or
  `vertical` and needs at least three shapes. Bounds are rotation-aware.
- **Protection**: shape locks and locked layers are honored. Locked shapes may
  anchor an alignment/distribution but are never moved or structurally edited.
- **Ids of existing shapes**: get them from `explain` (CLI/MCP) or
  `list_shapes` (file/live). New shapes get the next free id automatically.
- **Fidelity**: only changed cells are rewritten; unmodified shapes, formulas,
  themes, and unknown parts pass through byte-for-byte.
- Unknown ops / bad references are logged and skipped, never fatal.

### CLI / MCP

```bash
vsdxtool patch -i diagram.vsdx --ops ops.json [--page 0] [-o out.vsdx]
```
MCP file: `apply_ops({ "path": "diagram.vsdx", "page": 0, "ops": [ … ] })`
MCP live (running app, in-memory, instant):
`live_apply_ops({ "page": 0, "ops": [ … ] })`

`page` is a zero-based page index. It defaults to page 0 for file edits and
the current page for live edits. The convenience edit tools accept the same
optional `page`. Use `list_pages` to discover tab indices/stable ids and
`select_page` to switch the visible tab in the running app. Use `list_layers`
to discover stable layer ids and memberships; `select_layer` selects all
visible, editable objects explicitly assigned to one layer in the live app.
