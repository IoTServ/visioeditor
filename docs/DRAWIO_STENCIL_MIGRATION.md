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

## Migrated in the JavaScript Canvas pass

- 63 draw.io sidebar sections and 959 JavaScript-painted shape variants.
- AWS 3D, ArchiMate 2.1 and 3.2, Android, Arrows 2, BPMN events and
  gateways, C4, DFD, Electrical, Floorplan, GCP 2 cards, iOS, Infographic,
  Lean Mapping, SysML and UML 2.5 are among the captured families.
- The generator executes the vendored draw.io shape painters against a
  recording Canvas. Paths are converted to the same native geometry used by
  XML stencils; JavaScript never runs in the application.
- Entries that depend on an external image, icon font or unresolved embedded
  stencil are rejected instead of being replaced by a generic outline.

Regenerate this catalog with:

```sh
python3 tool/generate_drawio_js_stencils.py
```

Together, the two passes expose 266 extended libraries and 9,923 shapes. All
9,923 pass the Flutter Canvas render audit; representative XML and JavaScript
shapes also pass VSDX writer/parser round-trip tests.

## Remaining migration work

The following draw.io libraries are still not represented completely:

- compressed `addDataEntry` composite models, group templates and edge-only
  entries used by Advanced, C4, ER, SysML, Threat Modeling and UML 2.5;
- external-image or embedded-stencil variants in Active Directory, Allied
  Telesis, Cisco 19/SAFE, SAP, current cloud icon sets and Dynamics 365;
- icon-font-only variants from AWS 4b, Azure 2, GCP Icons and current iOS;
- exact draw.io “More Shapes” top-level/sub-library hierarchy and aliases for
  built-in mxGraph styles that already have equivalent project primitives.

Within migrated XML shapes, geometry and connection points are preserved, but
these draw.io paint instructions still need a later fidelity pass:

- embedded decorative `<text>` operations and exact font metrics;
- per-subpath colour, opacity, dash, cap and join changes;
- remaining conditional/composite templates and icon-font glyphs.

These limitations affect styling detail, not shape identity: migrated entries
use their source contours and never substitute a generic placeholder shape.
