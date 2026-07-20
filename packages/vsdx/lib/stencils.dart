/// Public stencil catalog — the draw.io-style shape library ([Stencil],
/// [StencilGroup], [kStencilGroups], [kStencils]).
///
/// Lives in the engine package so **both** the editor UI and the Agent build
/// path (`package:vsdx/agent.dart`) can reuse the same ~300 shapes. Each
/// [Stencil.build] produces a pure-`VsdxShape` at a page-inch centre, so shapes
/// round-trip through the writer unchanged.
library;

export 'src/stencils.dart';
export 'src/chart_stencils.dart';
