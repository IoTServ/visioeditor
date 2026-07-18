# Style presets

Named palettes for Diagram Spec builds (aligned with drawio-skill `styles/`).

| Name | Use when |
| --- | --- |
| `default` | General diagrams (draw.io blue/green defaults) |
| `corporate` | Business / architecture decks (cooler blues, sharper rectangles) |
| `dark` | Dark backgrounds / night themes |

## How to apply

1. Spec field: `{ "style": "corporate", "nodes": [ { "id": "db", "role": "database", … } ] }`
2. CLI: `VSDXTOOL build -s spec.json -o out.vsdx --style dark`
3. MCP: `create_diagram({ spec, style: "corporate" })` or `list_styles`

## Node `role` → palette

`service` · `database` · `queue` · `gateway` · `error` · `external` · `security`

Roles also hint stencils when the node still uses the default `rectangle`
(e.g. `database` → `cylinder`). Explicit `fill` / `line` / `stencil` always win.

Engine source of truth: `packages/vsdx/lib/src/agent/style_presets.dart`.
