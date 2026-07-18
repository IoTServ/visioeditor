# Styling

## Colors

Colors are hex strings: `#RGB`, `#RRGGBB`, or `#AARRGGBB` (with or without `#`).
`"none"` means no fill / no line.

- `fill` — node interior. `line` — node/edge stroke. `textColor` — label color.
- Defaults: fill `#DAE8FC`, line `#6C8EBF`, text `#1F2937`.

## Semantic palette (recommended)

Use a small, consistent set. Fill + matching line:

| Role | Fill | Line |
| --- | --- | --- |
| Default / process | `#DAE8FC` | `#6C8EBF` |
| Success / data | `#D5E8D4` | `#82B366` |
| Warning / decision | `#FFF2CC` | `#D6B656` |
| Danger / external | `#F8CECC` | `#B85450` |
| Accent / service | `#E1D5E7` | `#9673A6` |
| Neutral / group | `#F5F5F5` | `#666666` |

Pick fills so labels stay legible with the default dark text; use `bold: true`
for titles/emphasis. Keep one accent per diagram, not a rainbow.

## Text

- `text` supports `\n` line breaks (useful for ERD/UML compartments).
- `bold` toggles weight. `textColor` overrides the default ink.
- For a title, use a `text` stencil node with `bold: true`, larger `w`.

## Layout knobs

- `layout.direction`: `TB` (flow/org) vs `LR` (pipelines/timelines).
- `layout.spacing`: increase (e.g. `0.9`) when labels are long or edges crowd.
- Prefer auto-layout; hand-place only when exact positions matter.

## Advanced styling

Gradients, dashed lines, arrow types, shadows, themes, rich multi-run text,
etc. are supported by the engine but not yet exposed in the Diagram Spec.
Generate the structure here, then open in the app to apply advanced formatting
(the app's Format panel mirrors draw.io). Exposing more of these to the Agent
is planned — see `docs/MCP_SKILL_PLAN.md`.
