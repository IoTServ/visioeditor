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

## Full library (600+ shapes)

The **entire** shape library is available to the Agent — not just the core set.
Use any library shape's display name as `stencil` (case- and space-insensitive):
e.g. `"Cloud"`, `"Class"` (UML), `"Cisco Router"`, `"EC2"` / `"S3"` / `"Lambda"`
(AWS), `"Firewall"`, `"Pool"` / `"Lane"` (swimlanes), `"Table"`, and hundreds
more across **General, Flowchart, Arrows, Basic, Containers, UML, ER, BPMN,
Network, Mockup, Electrical, Signs, Floorplan, EIP, AWS, Azure, GCP, Cisco,
Alibaba, IBM, Oracle** groups.

Resolution order: curated core (clean size + fill control) → full catalog
(resized to your `w`/`h`; `fill`/`line` applied only when you set them, else the
shape's own styling is kept) → rectangle fallback.

**Discover exact names** with search (don't guess):

```bash
vsdxtool shapes search "aws"       # EC2, S3, Lambda, VPC, RDS, DynamoDB, …
vsdxtool shapes search "firewall"  # ASA Firewall, Azure Firewall, Firewall, …
```
MCP: `search_shapes({ "query": "uml" })`. Then pass the returned name as
`stencil`.
