# Shape catalog (`stencil` names)

Use these as a node's `stencil` (build) or `add_shape.stencil` (edit). Names are
case-insensitive and alias-aware; an unknown name falls back to `rectangle`.

All shapes use white-listed geometry, so they round-trip through the writer
unchanged and render identically in Visio / the app.

| Canonical | Group | Aliases | Looks like |
| --- | --- | --- | --- |
| `rectangle` | General | `process`, `box`, `node`, `task`, `step` | rectangle (process) |
| `rounded` | General | `roundedrectangle`, `roundrect` | rounded rectangle |
| `ellipse` | General | `oval`, `circle` | ellipse |
| `terminator` | Flowchart | `start`, `end`, `state` | pill/ellipse (start/end) |
| `diamond` | Flowchart | `decision`, `condition`, `gateway` | decision diamond |
| `data` | Flowchart | `parallelogram`, `io`, `input`, `output` | I/O parallelogram |
| `hexagon` | Flowchart | `preparation` | hexagon |
| `triangle` | General | — | triangle |
| `cylinder` | Containers | `database`, `db`, `store`, `storage` | database cylinder |
| `text` | General | `textbox`, `label`, `note` | text box (no fill/line) |

## Finding a shape

```bash
vsdxtool shapes search database     # -> cylinder [Containers] (aka database, db, …)
```
MCP: `search_shapes({ "query": "database" })`.

## Note on the full library

The desktop app ships **~300** stencils (AWS/Azure/GCP/Cisco, network, UML,
BPMN, ERD, EIP, floorplan, electrical, …). The Agent build path currently
exposes the **curated core set** above (enough for flowcharts, org charts,
architecture, ERD-ish, and swimlane-style diagrams). To use a specialized
shape today, build the structure with core stencils and open it in the app to
swap in a library shape; full-catalog exposure to the Agent is planned
(see `docs/MCP_SKILL_PLAN.md` M5).
