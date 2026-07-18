# Diagram-type presets

Conventions per common type: layout direction, stencils, and palette. All are
starting points — adapt to the request.

Palette (semantic, draw.io-like):

| Role | Fill | Line |
| --- | --- | --- |
| Default / process | `#DAE8FC` | `#6C8EBF` |
| Success / data store | `#D5E8D4` | `#82B366` |
| Warning / decision | `#FFF2CC` | `#D6B656` |
| Danger / external | `#F8CECC` | `#B85450` |
| Accent / service | `#E1D5E7` | `#9673A6` |
| Neutral | `#F5F5F5` | `#666666` |

---

## Flowchart / process

- `direction: TB`. `terminator` for start/end, `process` for steps,
  `decision` for branches, `data` for I/O.
- Label decision out-edges (`yes`/`no`). Keep one main vertical spine.

## Org chart

- `direction: TB`. `rectangle`/`rounded` boxes; top = leader, edges = reports.
- Bold the top node; consistent box sizes per tier.

## Architecture / microservices

- `direction: TB` (tiers: clients → gateway → services → data) or `LR`.
- `process`/`rounded` for services, `cylinder` for databases/caches,
  `terminator`/`ellipse` for external actors. Color by tier (accent for
  services, success for data stores, danger for third-party).

## Network topology

- `direction: TB`. `rectangle` for devices, `cylinder` for storage,
  `ellipse` for clouds/internet. Label links (protocol / bandwidth).
- Use the app's Network library for real device icons after generating.

## ERD (entity-relationship)

- `direction: LR` or `TB`. One `rectangle` per entity; put fields in the
  `text` with `\n` (e.g. `Order\n──────\nid (PK)\ncustomer_id (FK)`).
- Edges = relationships; label cardinality (`1..*`).

## UML class (lightweight)

- `rectangle` per class; `text` = `ClassName\n───\n+field\n───\n+method()`.
- Edges for associations/inheritance; label the relation.

## BPMN (lightweight)

- `direction: LR`. `ellipse` for events, `rounded` for tasks, `diamond` for
  gateways. Label sequence flows.

## Swimlane / cross-functional

- Model lanes as large `rectangle` containers (or generate the flow, then use
  the app's Pool/Lane stencils to wrap it). `direction: LR` for the process,
  one row per role.

---

Tip: for most types, omit coordinates and let auto-layout place nodes; only
hand-place when the user needs an exact arrangement.
