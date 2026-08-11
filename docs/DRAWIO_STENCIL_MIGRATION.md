# draw.io stencil migration

Baseline: draw.io 30.3.6, commit `43c1dfa7db49cca465312c00e9ed8b85b4195a7c`
(2026-07-09).

## Migrated in the XML catalog pass

- 203 XML stencil libraries exposed as selectable “More shapes” categories.
- 8,964 named shapes converted lazily to native `VsdxGeometry`.
- 49 source families, including Alibaba Cloud, Android, AWS generations,
  Azure, BPMN, Cisco/Cisco SAFE, Citrix, Electrical, Floorplan, Fluid Power,
  GCP, IBM, iOS 7, Kubernetes, Mockups, Microsoft Cloud and Enterprise,
  Network, Office, OpenStack, P&ID, Rack, Salesforce, Signs, Veeam and Web
  Icons.
- Paths, lines, cubic/quadratic curves, SVG elliptical arcs, rectangles,
  rounded rectangles, ellipses, fill/stroke boundaries and connection points.
- Every migrated shape is decoded and sent through the Flutter Canvas path
  renderer by an automated test. Representative curve, arc, ellipse and
  connection-point shapes also pass VSDX writer/parser round-trip tests.

The generated catalog is self-contained. Regenerate it from a local draw.io
checkout with:

```sh
python3 tool/generate_drawio_xml_stencils.py
```

## Remaining migration work

The following draw.io libraries are defined primarily or exclusively by
JavaScript template builders rather than the 203 XML stencil files. They are
not yet represented completely:

- Active Directory, Allied Telesis, ArchiMate and ArchiMate 3
- AWS 4b, Azure 2 and Google Cloud icon-font variants
- C4, DFD, Threat Modeling, SysML and UML 2.5
- Cumulus, Dynamics 365, Infographic, SAP and current iOS UI templates
- Some composite templates from Advanced, Arrows 2, ER and Network

Within migrated XML shapes, geometry and connection points are preserved, but
these draw.io paint instructions still need a later fidelity pass:

- embedded decorative `<text>` operations and exact font metrics;
- per-subpath colour, opacity, dash, cap and join changes;
- JavaScript-only variables, conditional templates and icon-font glyphs.

These limitations affect styling detail, not shape identity: migrated entries
use their source contours and never substitute a generic placeholder shape.
