---
name: visioeditor-skill
version: 0.1.0
description: Use when the user wants a Microsoft Visio (.vsdx) diagram — flowcharts, org charts, network / architecture diagrams, ERD, UML, BPMN, swimlanes — or wants to generate or edit .vsdx from natural language, code, or data, optionally with live preview in the visioeditor desktop app. Produces round-trip-faithful, re-editable .vsdx (not lossy images) via the pure-Dart `vsdxtool` CLI or the `visioeditor` MCP server. Prefer this over hand-writing OPC/XML.
license: MIT
homepage: https://github.com/  (this repo)
compatibility: Requires the Dart SDK (to run `vsdxtool`) or a compiled `vsdxtool` binary. Live preview requires the visioeditor desktop app with "Agent live preview" enabled (More ⋯ menu). Visual self-check requires a vision-enabled model.
platforms: [macos, linux, windows]
---

# visioeditor — Text / Data → editable .vsdx

## Overview

Turn a natural-language request (or code / data) into a **Microsoft Visio
`.vsdx`** file that stays fully editable in Visio, LibreOffice, 万兴图示, and the
visioeditor app. Two interchangeable backends, same engine:

- **`vsdxtool` CLI** — headless, pure Dart. Best for file work (build / edit /
  render / validate).
- **`visioeditor` MCP server** — the same tools over MCP, **plus live tools**
  that drive the *running* desktop app for real-time preview.

Unlike drawio's Electron CLI, everything here is headless Dart — fast, no
browser — and can push edits into the live app so the user watches the diagram
build itself.

## When to use / when NOT to use

**Use this skill for:** Visio `.vsdx` deliverables — flowcharts, org charts,
architecture / network diagrams, ERD, UML, BPMN, swimlanes — anything the user
will open/edit in Visio, or wants previewed live in the visioeditor app.

**Route elsewhere for:** `.drawio` output (use a draw.io skill), Mermaid-in-
Markdown (mermaid), hand-drawn/whiteboard looks (excalidraw/tldraw).

## Bundled resources

Read on demand — none need to be in context up front.

| File | Read it when |
| --- | --- |
| `references/spec-schema.md` | You're about to write a **Diagram Spec** (build) or **Edit Ops** (edit) — the full JSON schema, every field, defaults, and examples |
| `references/shape-catalog.md` | You need the right `stencil` name for a node (aliases, groups) or want `search_shapes` usage |
| `references/diagram-types.md` | The user names a diagram type (flowchart, org chart, architecture, network, ERD, UML, BPMN, swimlane) — layout direction, stencils, and color conventions per type |
| `references/styling.md` | Applying colors / a palette / semantic conventions (fills, lines, text) |
| `references/live-preview.md` | You want the diagram to appear/update **live in the running app**, or need to configure the MCP server in Cursor / Claude |
| `references/troubleshooting.md` | A command fails, the bridge won't connect, or a render looks wrong |

## Prerequisites — resolve the `vsdxtool` command once

Try, in order, and reuse the first that works as `VSDXTOOL` for the rest of the
session:

1. A compiled binary on PATH: `vsdxtool version`
2. From this repo: `cd packages/vsdx && dart run bin/vsdxtool.dart version`

To build the binaries once (fast, single-file, no deps):

```bash
cd packages/vsdx
dart compile exe bin/vsdxtool.dart     -o vsdxtool
dart compile exe bin/vsdxtool_mcp.dart -o vsdxtool-mcp
```

If using the **MCP server** instead of the CLI, register it once (see
`references/live-preview.md`) and call its tools (`create_diagram`,
`apply_ops`, `export`, `validate`, `explain`, `search_shapes`, and the live
tools `open_in_app` / `live_apply_ops` / `select` / `snapshot` / `get_app_state`).

## Workflow

Assess the request first. If key details are missing, ask 1–3 focused
questions (diagram type? key components/labels? live preview in the app?).
Skip clarification for simple, clear asks ("draw a flowchart of X").

1. **Check tool** — resolve `VSDXTOOL` (above). Detect live preview: if the
   user wants it, ensure the app is running with "Agent live preview" on
   (a handshake file at `~/.visioeditor/agent-bridge.json` means it's ready).
2. **Plan** — pick the diagram type preset (`references/diagram-types.md`):
   shapes, relationships, layout direction (`TB` for flow/org, `LR` for
   pipelines), grouping. For unfamiliar shapes, `search_shapes "<keywords>"`.
3. **Generate a Diagram Spec** (JSON) — nodes + edges; omit coordinates to let
   the layered auto-layout place them (`references/spec-schema.md`). Then:
   - CLI: `VSDXTOOL build -s spec.json -o out.vsdx`
   - MCP: `create_diagram({ spec, path, open: true })`
4. **Validate** — `VSDXTOOL validate -i out.vsdx` (or the `validate` tool).
   Fix any errors (dangling connectors, off-page, overlaps) before showing.
5. **Preview**
   - **Live (preferred):** `open_in_app` once, then build incrementally with
     `live_apply_ops` — the user sees each step in the app. Or open the file
     and let the app auto-reload after each `build`/`patch`.
   - **Headless:** `VSDXTOOL render -i out.vsdx -o out.svg` for a quick look;
     `snapshot` (MCP, needs the app) returns a PNG for a visual self-check.
6. **Self-check (vision)** — read the PNG (from `snapshot`) and fix obvious
   issues (overlaps, clipped labels, connectors crossing shapes) with targeted
   Edit Ops. Max 2 rounds. See "Self-check" below.
7. **Iterate** — show the user, collect feedback, apply minimal Edit Ops
   (`apply_ops` / `live_apply_ops`), re-preview. Up to 5 rounds.
8. **Deliver** — report the `.vsdx` path (and `.svg` if requested). It opens
   in Visio / the visioeditor app for fine-tuning.

## Editing an existing diagram

Never regenerate the whole file for a small change — use **Edit Ops** so the
save is round-trip faithful (only changed cells are rewritten; formulas and
unknown structure pass through untouched):

```bash
VSDXTOOL patch -i diagram.vsdx --ops ops.json     # file
# or MCP: apply_ops({ path, ops })  /  live_apply_ops({ ops })  for the live app
```

Get current shape ids with `list_shapes` (MCP; JSON of id/text/x/y/w/h, file or
live) or `explain` (`VSDXTOOL explain -i file.vsdx`). Reference shapes as
`"shape:<id>"` or the raw id. With live preview on, `select({ ids })`
highlights those shapes in the editor (empty list clears).

**Convenience single-step tools** (MCP) avoid hand-building op arrays:
`add_shape`, `add_connector`, `set_style`, `set_text`, `move_shape`,
`delete_shape`. Each takes an optional `path` — give it to edit a **file**,
omit it to edit the **running app** live.

## Importers (structure in → editable .vsdx)

When the user already has the structure, import it instead of hand-writing a
spec:

- **Mermaid** flowchart/graph → `VSDXTOOL import-mermaid -i flow.mmd -o out.vsdx`
  (MCP: `import_mermaid({ text, path, open })`). Node shapes, edge labels, and
  direction are mapped automatically.
- **SQL DDL** (`CREATE TABLE …`) → ER diagram:
  `VSDXTOOL import-sql -i schema.sql -o erd.vsdx`
  (MCP: `import_sql({ sql, path, open })`). Tables become boxes with columns +
  PK/FK markers; foreign keys become edges.
- **Codebase** (Dart / Python / JS-TS / Go / Rust) → module/package import graph:
  `VSDXTOOL import-code -d ./src -o code.vsdx` (MCP: `import_code({ dir,
  language?, path, open })`). One box per module (per package for Go via
  `go.mod`; Rust modules via `mod` / `use crate|super|self`, `foo/mod.rs`
  collapsed); edges are intra-project imports (external/SDK dropped). Auto-detected.
- **OpenAPI / Swagger** (JSON or YAML) → API diagram:
  `VSDXTOOL import-openapi -i openapi.yaml -o api.vsdx`
  (MCP: `import_openapi({ spec, path, open })`). Operations coloured by HTTP
  method + schema boxes + `$ref` edges.
- **IaC** (docker-compose / Kubernetes YAML / Terraform HCL) → architecture diagram:
  `VSDXTOOL import-iac -i docker-compose.yml -o infra.vsdx`
  (also `.tf` — resources/modules/data + `depends_on` / reference edges)
  (MCP: `import_iac({ yaml, path, open })`). Auto-detected: compose services +
  `depends_on`/volumes; k8s resources by kind + Service/Ingress/volume edges;
  Terraform resources/modules/data + reference edges.

Both produce a normal `.vsdx` you can then refine with Edit Ops and preview
live.

**Reverse** — describe or convert an existing `.vsdx`:
`explain` → structured Markdown; `to-mermaid` (MCP `to_mermaid`) → a Mermaid
flowchart to drop into a GitHub-rendered README.

## Diagram Spec — quick reference

```jsonc
{
  "title": "Order Flow",
  "layout": { "direction": "TB", "spacing": 0.7 },   // TB (top→bottom) or LR
  "nodes": [
    { "id": "a", "stencil": "terminator", "text": "Start" },
    { "id": "b", "stencil": "process",    "text": "Validate", "fill": "#DAE8FC" },
    { "id": "c", "stencil": "decision",   "text": "OK?" },
    { "id": "d", "stencil": "cylinder",   "text": "Order DB", "fill": "#D5E8D4" }
  ],
  "edges": [
    { "from": "a", "to": "b" },
    { "from": "b", "to": "c" },
    { "from": "c", "to": "d", "label": "yes" }
  ]
}
```

Omit `x`/`y` to auto-layout. Common core stencils: `process` (rectangle),
`rounded`, `terminator`/`ellipse`, `decision` (diamond), `data`
(parallelogram), `hexagon`, `cylinder` (database), `text`. **The full ~600-shape
library is also available** — pass any library shape's display name as
`stencil` (e.g. `"Cloud"`, `"Class"`, `"EC2"`, `"Cisco Router"`, `"Pool"`).
Use `search_shapes` to find exact names; details in `references/shape-catalog.md`.

## Edit Ops — quick reference

```jsonc
{ "ops": [
  { "op": "add_shape",     "stencil": "process", "text": "Ship", "x": 6, "y": 5 },
  { "op": "add_connector", "from": "shape:4", "to": "shape:7", "label": "ok" },
  { "op": "set_style",     "ids": ["shape:4"], "fill": "#D5E8D4", "line": "#82B366" },
  { "op": "set_text",      "id": 7, "text": "Ship order" },
  { "op": "move_shape",    "id": 7, "x": 8, "y": 5 },
  { "op": "resize_shape",  "id": 7, "w": 2.0, "h": 1.0 },
  { "op": "delete_shape",  "id": 3 }
] }
```

## Self-check (vision)

After a `snapshot`, read the PNG and fix before showing the user:

| Check | Fix with |
| --- | --- |
| Overlapping shapes | `move_shape` apart, or increase `spacing` and rebuild |
| Clipped labels | `resize_shape` larger, or shorten text |
| Connector crosses a shape | `move_shape` the obstacle, or rebuild (auto-layout routes around) |
| Off-page shapes | `move_shape` onto the page (see `validate` output for ids) |

Prefer a **full rebuild** (regenerate the spec) for layout-wide problems;
prefer **Edit Ops** for single-element tweaks (keeps prior tuning).

## Colors

Default palette is draw.io-like (`#DAE8FC` fill / `#6C8EBF` line). Use a
consistent, semantic palette; details in `references/styling.md`.
