/// Pure-Dart Microsoft Visio (.vsdx / OPC) engine.
///
/// Public surface of `package:vsdx`: the editable document model, the OPC/XML
/// reader, formula (read-only) evaluation, and shared core/utils. The
/// round-trip writer lands under `src/writer/` in milestone E4.
///
/// See `docs/ARCHITECTURE.md` and `docs/REUSE_MAP.md`.
library;

// core
export 'src/core/exceptions.dart';
export 'src/core/result.dart';
export 'src/core/diagnostics.dart';
export 'src/core/version.dart';

// utils
export 'src/utils/units.dart';
export 'src/utils/color.dart';
export 'src/utils/transform.dart';
export 'src/utils/xml_extensions.dart';

// model
export 'src/model/connect.dart';
export 'src/model/custom_property.dart';
export 'src/model/document.dart';
export 'src/model/document_settings.dart';
export 'src/model/effects.dart';
export 'src/model/fill.dart';
export 'src/model/geometry.dart';
export 'src/model/hyperlink.dart';
export 'src/model/image.dart';
export 'src/model/layer.dart';
export 'src/model/line.dart';
export 'src/model/master.dart';
export 'src/model/obstacle_router.dart';
export 'src/model/page.dart';
export 'src/model/perimeter.dart';
export 'src/model/rich_text.dart';
export 'src/model/rich_text_edit.dart';
export 'src/model/shape.dart';
export 'src/model/shape_factory.dart';
export 'src/model/shape_kind.dart';
export 'src/model/sheet_sections.dart';
export 'src/model/stylesheet.dart';
export 'src/model/swimlane.dart';
export 'src/model/table.dart';
export 'src/model/theme.dart';
export 'src/model/user_property.dart';

// parser (entry points)
export 'src/parser/package_reader.dart';
export 'src/parser/relationships.dart';
export 'src/parser/document_parser.dart';
export 'src/parser/formula.dart';
export 'src/parser/parse_visio.dart';
export 'src/parser/emf_embedded_bitmap.dart';
export 'src/parser/vsd/vsd_document_parser.dart';
export 'src/parser/vsd/cfb/compound_file.dart';

// writer (round-trip save)
export 'src/writer/vsdx_writer.dart';

// export (interop)
export 'src/export/svg_serializer.dart';
export 'src/export/theme_serializer.dart';

/// Engine version, surfaced in diagnostics and the app About box.
const String kVsdxEngineVersion = '0.1.0';
