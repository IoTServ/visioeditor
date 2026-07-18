/// The stencil catalog now lives in the engine package (`package:vsdx`) so the
/// Agent build path can reuse the full library. Re-exported here so the editor
/// UI's existing `import '.../editor/stencils.dart'` call sites are unchanged.
export 'package:vsdx/stencils.dart';
