/// Visio binary (VSD5 / VSD6 / VSD11) parser → [VsdxDocument].
///
/// Stream / chunk layout follows the publicly documented Visio binary structure
/// (algorithm reference: LibreOffice libvisio `VSDParser` / `VSD5Parser`).
/// Independent Dart implementation — no C++ source is copied.
library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../model/connect.dart';
import '../../model/document.dart';
import '../../model/effects.dart';
import '../../model/fill.dart';
import '../../model/geometry.dart';
import '../../model/hyperlink.dart';
import '../../model/image.dart';
import '../../model/layer.dart';
import '../../model/line.dart';
import '../../model/page.dart';
import '../../model/rich_text.dart';
import '../../model/shape.dart';
import '../../model/sheet_sections.dart';
import '../../model/user_property.dart';
import '../../utils/color.dart';
import '../shape_kind_detector.dart';
import 'vsd_byte_reader.dart';
import 'vsd_internal_stream.dart';
import 'vsd_record_ids.dart';
import 'vsd_text_codec.dart';

const int _minusOne = 0xFFFFFFFF;

class _VsdFontInfo {
  const _VsdFontInfo(this.name, this.encoding);

  final String name;
  final VsdLegacyTextEncoding encoding;
}

class _LegacyTextSpan {
  const _LegacyTextSpan(this.start, this.end, this.encoding);

  final int start;
  final int end;
  final VsdLegacyTextEncoding encoding;
}

/// Reorder list items by trailer id sequence (CharList / ParaList / FieldList).
///
/// Ids present in [order] come first (first occurrence wins); remaining items
/// keep relative encounter order. Used by VSD6/11 list trailers.
List<T> vsdReorderById<T>(
  List<T> items,
  List<int> order,
  int Function(T) idOf,
) {
  if (order.isEmpty || items.isEmpty) return items;
  final byId = <int, T>{};
  for (final item in items) {
    byId.putIfAbsent(idOf(item), () => item);
  }
  final out = <T>[];
  final seen = <int>{};
  for (final id in order) {
    final item = byId[id];
    if (item != null && seen.add(id)) out.add(item);
  }
  for (final item in items) {
    final id = idOf(item);
    if (seen.add(id)) out.add(item);
  }
  return out;
}

/// Converts the signed word stored by Visio 5 to libvisio's unsigned value.
///
/// `VSD5Parser::getUInt` sign-extends the 16-bit word and then casts it to an
/// unsigned 32-bit integer, so values such as -2 must remain `0xfffffffe`.
int vsdV5UnsignedInt(int signedValue) => signedValue & 0xffffffff;

typedef VsdShapeXFormValues = ({
  double pinX,
  double pinY,
  double width,
  double height,
  double locPinX,
  double locPinY,
});

/// Default binary VSD shape transform, matching libvisio's `XForm()`.
const VsdShapeXFormValues vsdDefaultShapeXForm = (
  pinX: 0,
  pinY: 0,
  width: 0,
  height: 0,
  locPinX: 0,
  locPinY: 0,
);

typedef VsdPagePropsValues = ({
  double pageWidth,
  double pageHeight,
  double pageScale,
  double drawingScale,
  double scale,
});

/// Applies the binary VSD PageProps normalization used by libvisio.
///
/// Unlike VSDX, binary VSD clamps negative page dimensions, takes the absolute
/// drawing ratio, and treats a DrawingScale within `VSD_EPSILON` of zero as 1.
/// Zero page dimensions and a zero PageScale remain valid values.
VsdPagePropsValues vsdNormalizePageProps({
  required double pageWidth,
  required double pageHeight,
  required double pageScale,
  required double drawingScale,
}) {
  final normalizedDrawingScale =
      drawingScale.abs() <= 1e-6 ? 1.0 : drawingScale;
  return (
    pageWidth: pageWidth < 0 ? 0.0 : pageWidth,
    pageHeight: pageHeight < 0 ? 0.0 : pageHeight,
    pageScale: pageScale,
    drawingScale: normalizedDrawingScale,
    scale: (pageScale / normalizedDrawingScale).abs(),
  );
}

/// Formats the time-bearing field codes handled by libvisio.
///
/// Returns `null` when [format] is a date-only or non-date field code.
String? vsdFormatVisioTimeField(DateTime dateTime, int format) {
  final dt = dateTime.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final amPm = dt.hour >= 12 ? 'PM' : 'AM';
  switch (format) {
    case 30: // TimeGen: h:mm:ss tt
      return '${two(hour12)}:${two(dt.minute)}:${two(dt.second)} $amPm';
    case 31:
    case 32:
    case 33:
    case 34:
      // libvisio emits seconds for all four legacy h:mm / H:mm codes.
      return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    case 35:
    case 36:
      return '${two(hour12)}:${two(dt.minute)} $amPm';
    case 46:
    case 66:
    case 67:
    case 68:
    case 69:
    case 70:
    case 71:
    case 72:
    case 73:
    case 74:
    case 75:
    case 80:
    case 81:
      // Stable C-locale equivalent of libvisio's `%X` output.
      return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    case 211:
    case 212:
      final date = '${two(dt.month)}/${two(dt.day)}/${dt.year}';
      final seconds = format == 212 ? ':${two(dt.second)}' : '';
      return '$date ${two(hour12)}:${two(dt.minute)}$seconds $amPm';
    case 213:
      return '${two(hour12)}:${two(dt.minute)} $amPm';
    case 214:
      return '${two(hour12)}:${two(dt.minute)}:${two(dt.second)} $amPm';
    case 215:
      return '${two(dt.hour)}:${two(dt.minute)}';
    case 216:
      return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    default:
      return null;
  }
}

/// Resolves ShapeList element ids to the actual Shape ids stored by ShapeId.
///
/// libvisio keeps the two collections separately because a list trailer orders
/// record ids, not shape ids. Without a trailer, record-id order is used.
List<int> vsdResolveShapeOrder(
  Map<int, int> elementToShapeId,
  List<int> elementOrder,
) {
  if (elementToShapeId.isEmpty) return const [];
  if (elementOrder.isNotEmpty) {
    return [
      for (final elementId in elementOrder)
        if (elementToShapeId[elementId] case final shapeId?) shapeId,
    ];
  }
  final entries = elementToShapeId.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return [for (final entry in entries) entry.value];
}

typedef VsdDynamicNurbsFormula = ({
  double lastKnot,
  int degree,
  bool xRelative,
  bool yRelative,
  List<Offset2D> controlPoints,
  List<double> knots,
  List<double> weights,
});

/// Combines a `NURBSTo` row with its referenced ShapeData block.
///
/// ShapeData stores only the interior knot/weight sequence and the final knot;
/// Visio keeps the first and penultimate knots plus endpoint weights on the
/// geometry row. libvisio joins them in this exact order before sampling.
({List<double> knots, List<double> weights}) vsdAssembleNurbsShapeData({
  required List<double> dataKnots,
  required List<double> dataWeights,
  required double firstKnot,
  required double secondLastKnot,
  required double lastKnot,
  required double firstWeight,
  required double lastWeight,
}) =>
    (
      knots: [firstKnot, ...dataKnots, secondLastKnot, lastKnot],
      weights: [firstWeight, ...dataWeights, lastWeight],
    );

/// Resolves a ShapeData id, including libvisio's `0xfffffffe` master sentinel.
T? vsdResolveShapeDataReference<T>({
  required int dataId,
  required Map<int, T> localData,
  Map<int, T>? masterData,
  int? masterDataId,
}) {
  if (dataId != 0xfffffffe) return localData[dataId];
  if (masterData == null || masterDataId == null) return null;
  return masterData[masterDataId];
}

/// Reads the typed-parameter form of a binary NURBS formula.
///
/// Unlike the static `0x8a` form, every coordinate, knot and weight carries a
/// value-type byte. This mirrors libvisio's complex `readNURBSTo` branch.
VsdDynamicNurbsFormula vsdReadDynamicNurbsFormula(
  VsdByteReader input, {
  required int firstValueType,
  required int blockLength,
  required int payloadStart,
}) {
  final lastKnot = firstValueType == 0x20
      ? input.readF64()
      : input.readU16().toDouble();
  input.skip(1);
  final degree = input.readU16();
  input.skip(1);
  final xType = input.readU16();
  input.skip(1);
  final yType = input.readU16();

  final controlPoints = <Offset2D>[];
  final knots = <double>[];
  final weights = <double>[];
  var bytesRead = input.offset - payloadStart;
  var flag = input.readU8();
  while (flag != 0x81 && bytesRead < blockLength && !input.isEnd) {
    final parameterStart = input.offset;
    final x = flag == 0x20 ? input.readF64() : input.readU16().toDouble();
    final yFlag = input.readU8();
    final y =
        yFlag == 0x20 ? input.readF64() : input.readU16().toDouble();
    final knotFlag = input.readU8();
    final knot = switch (knotFlag) {
      0x20 => input.readF64(),
      0x62 => input.readU16().toDouble(),
      _ => 0.0,
    };
    final weightFlag = input.readU8();
    final weight = switch (weightFlag) {
      0x20 => input.readF64(),
      0x62 => input.readU16().toDouble(),
      _ => 0.0,
    };
    controlPoints.add(Offset2D(x, y));
    knots.add(knot);
    weights.add(weight);
    flag = input.readU8();
    bytesRead += input.offset - parameterStart;
  }

  return (
    lastKnot: lastKnot,
    degree: degree,
    xRelative: xType == 0,
    yRelative: yType == 0,
    controlPoints: controlPoints,
    knots: knots,
    weights: weights,
  );
}

/// Resolves the page-level shadow offsets inherited by VSD5/VSD6
/// FillAndShadow records.
///
/// libvisio keeps PageProps separately for the active stencil page. A master
/// shape must inherit those values instead of the drawing page (which is not
/// active while the stencil stream is being parsed).
({double x, double y}) vsdResolveLegacyShadowOffsets({
  required bool isStencil,
  required double stencilX,
  required double stencilY,
  required double pageX,
  required double pageY,
}) => isStencil ? (x: stencilX, y: stencilY) : (x: pageX, y: pageY);

class _GeomBuilder {
  _GeomBuilder();
  bool noFill = false;
  bool noLine = false;
  bool noShow = false;
  final commands = <VsdxPathCommand>[];
  final order = <int>[];
  final byId = <int, VsdxPathCommand>{};
  final polylineDataIds = <int, int>{};
  final nurbsDataIds = <int, int>{};
  int? geometryFlagsId;
}

class _ShapeDraft {
  _ShapeDraft();

  int id = 0;
  int parent = 0;
  int masterPage = _minusOne;
  int masterShape = _minusOne;
  int lineStyleId = _minusOne;
  int fillStyleId = _minusOne;
  int textStyleId = _minusOne;
  double pinX = vsdDefaultShapeXForm.pinX;
  double pinY = vsdDefaultShapeXForm.pinY;
  double width = vsdDefaultShapeXForm.width;
  double height = vsdDefaultShapeXForm.height;
  double locPinX = vsdDefaultShapeXForm.locPinX;
  double locPinY = vsdDefaultShapeXForm.locPinY;
  double angle = 0;
  bool flipX = false;
  bool flipY = false;
  bool hasXFormData = false;
  bool is1D = false;
  bool locked = false;
  bool dontMoveChildren = false;
  bool isTextEditTarget = false;
  int? selectMode;
  int? displayMode;
  double? beginX;
  double? beginY;
  double? endX;
  double? endY;
  int? beginTargetId;
  int? endTargetId;
  VsdxLine? line;
  VsdxFill? fill;
  VsdxShadow? shadow;
  String? text;
  Uint8List? legacyTextBytes;
  double? fontSizeInches;
  VsdxColor? textColor;
  bool bold = false;
  bool italic = false;
  bool hideText = false;
  bool hasMisc = false;
  String? fontFamily;
  VsdLegacyTextEncoding fontEncoding = VsdLegacyTextEncoding.ansi;
  String? shapeName;
  double? txtPinX;
  double? txtPinY;
  double? txtWidth;
  double? txtHeight;
  double? txtLocPinX;
  double? txtLocPinY;
  double? txtAngle;
  double? marginLeft;
  double? marginRight;
  double? marginTop;
  double? marginBottom;
  VsdxVertAlign? verticalAlign;
  VsdxColor? textBgColor;
  /// Whether TextBlock explicitly sets a filled text background.
  /// `false` = transparent (overrides master/style inheritance).
  bool? textBgFilled;
  double? defaultTabStop;
  int? textDirection;
  bool underline = false;
  bool smallCaps = false;
  VsdxTextCase textCase = VsdxTextCase.normal;
  VsdxTextPosition textPosition = VsdxTextPosition.normal;
  bool strikethrough = false;
  bool doubleUnderline = false;
  bool doubleStrikethrough = false;
  double fontScale = 1.0;
  VsdxHorzAlign? paraAlign;
  double? indFirst;
  double? indLeft;
  double? indRight;
  double? spLine;
  double? spBefore;
  double? spAfter;
  int? bullet;
  String? bulletStr;
  String? bulletFont;
  double? bulletFontSize;
  double? textPosAfterBullet;
  int? paraFlags;
  List<int> layerMemberIds = [];
  /// Child ShapeList record ids from the list trailer.
  final childOrder = <int>[];
  /// ShapeList record id → actual child shape id from ShapeId records.
  final childShapeIds = <int, int>{};
  final geometries = <_GeomBuilder>[];
  _GeomBuilder? currentGeom;
  Uint8List? foreignBytes;
  int foreignType = 0;
  int foreignFormat = 0;
  double? imgOffsetX;
  double? imgOffsetY;
  double? imgWidth;
  double? imgHeight;
  /// ShapeData polyline blobs keyed by chunk id (libvisio `m_polylineData`).
  final polylineData =
      <int, ({List<Offset2D> points, bool xRel, bool yRel})>{};
  /// ShapeData NURBS blobs keyed by chunk id.
  final nurbsData = <int,
      ({
        List<Offset2D> cps,
        List<double> knots,
        List<double> weights,
        double lastKnot,
        int degree,
        bool xRel,
        bool yRel,
      })>{};
  /// Pending PolylineTo rows that reference ShapeData by id.
  final pendingPolylineData = <
      ({
        int geometryIndex,
        int rowId,
        double x,
        double y,
        int dataId,
      })>[];
  /// Pending NURBSTo rows that reference ShapeData by id.
  final pendingNurbsData = <
      ({
        int geometryIndex,
        int rowId,
        double x,
        double y,
        double knot,
        double weight,
        double knotPrev,
        double weightPrev,
        int dataId,
      })>[];
  /// Text field display values in document order (for ￼ / 0x1E substitution).
  final fieldDisplays = <String>[];
  /// Parallel chunk ids for [fieldDisplays] (libvisio field list element ids).
  final fieldIds = <int>[];
  /// Parallel raw numeric fields for late format (DrawingUnits / VSD5 format
  /// byte). Null entries are string fields.
  final fieldRaw =
      <({double number, int cellType, int format, String? customFormat})?>[];
  /// Parallel deferred string-field references. Binary TextField records can
  /// precede their shape-local Name records, so resolving them while reading
  /// the chunk incorrectly falls back to an unrelated document Name2 entry.
  final fieldStringRefs =
      <({int nameId, int format, int formatStringId})?>[];
  /// Shape-local Name table (libvisio `m_shape.m_names`) — format ids /
  /// string-field payloads, NOT the shape display name.
  final localNames = <int, String>{};
  /// CharIX rows keyed by chunk id (libvisio `m_charList`).
  final charRuns = <_CharRunDraft>[];
  /// ParaIX rows keyed by chunk id (libvisio `m_paraList`).
  final paraRuns = <_ParaRunDraft>[];
  /// TabsData rows (libvisio `m_tabSets`).
  final tabRuns = <_TabSetDraft>[];
  /// Trailer order from CharList / ParaList / FieldList / TabsDataList.
  final charOrder = <int>[];
  final paraOrder = <int>[];
  final fieldOrder = <int>[];
  final tabOrder = <int>[];
  /// Connection point rows (ShapeSheet Connection section).
  final connectionPoints = <_ConnectionPointDraft>[];
  final connectionOrder = <int>[];
  /// Control handle rows (ShapeSheet Control section).
  final controls = <_ControlDraft>[];
  final controlOrder = <int>[];
  /// Shape Data rows (ShapeSheet Property section).
  final userProperties = <_UserPropDraft>[];
  final propOrder = <int>[];
  /// Scratch rows (ShapeSheet Scratch section).
  final scratchRows = <_ScratchDraft>[];
  final scratchOrder = <int>[];
  /// User-defined cells (ShapeSheet User section).
  final userCells = <_UserCellDraft>[];
  /// Actions rows (ShapeSheet Actions section).
  final actions = <_ActionDraft>[];
  final actionOrder = <int>[];
  /// Hyperlink rows (ShapeSheet Hyperlink section).
  final hyperlinks = <_HyperlinkDraft>[];
  final hyperlinkOrder = <int>[];
  /// ShapeSheet formulas (`F=`), e.g. EventDblClick → OPENTEXTWIN().
  final formulas = <String, String>{};
  /// Cached `V=` for EventDblClick when present.
  String? eventDblClick;
}

class _ConnectionPointDraft {
  int id = 0;
  double x = 0;
  double y = 0;
  double dirX = 0;
  double dirY = 0;
  int type = 0;
}

class _ControlDraft {
  int id = 0;
  double x = 0;
  double y = 0;
  double dynX = 0;
  double dynY = 0;
  double conX = 0;
  double conY = 0;
  bool canGlue = false;
  String? prompt;
  String? name;
}

class _UserPropDraft {
  int id = 0;
  String? name;
  String? label;
  String? value;
  String? prompt;
  String? format;
  int type = 0;
}

class _ScratchDraft {
  int id = 0;
  double x = 0;
  double y = 0;
  double a = 0;
  double b = 0;
  double c = 0;
  double d = 0;
}

class _UserCellDraft {
  int id = 0;
  String? name;
  String? value;
  String? prompt;
}

class _ActionDraft {
  int id = 0;
  String? name;
  String? menu;
  String? prompt;
}

class _HyperlinkDraft {
  int id = 0;
  String? description;
  String? address;
  String? subAddress;
  String? extraInfo;
  String? frame;
  bool newWindow = false;
  bool isDefault = false;
  bool invisible = false;
}

class _CharRunDraft {
  int id = 0;
  int charCount = 0;
  String? fontFamily;
  VsdLegacyTextEncoding encoding = VsdLegacyTextEncoding.ansi;
  double? fontSizeInches;
  VsdxColor? textColor;
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool smallCaps = false;
  VsdxTextCase textCase = VsdxTextCase.normal;
  VsdxTextPosition textPosition = VsdxTextPosition.normal;
  bool strikethrough = false;
  bool doubleUnderline = false;
  bool doubleStrikethrough = false;
  double fontScale = 1.0;
}

class _ParaRunDraft {
  int id = 0;
  int charCount = 0;
  VsdxHorzAlign? paraAlign;
  double? indFirst;
  double? indLeft;
  double? indRight;
  double? spLine;
  double? spBefore;
  double? spAfter;
  int? bullet;
  String? bulletStr;
  String? bulletFont;
  double? bulletFontSize;
  double? textPosAfterBullet;
  int? paraFlags;
}

class _TabSetDraft {
  int id = 0;
  int numChars = 0;
  final stops = <VsdxTabStop>[];
}

class _StyleDraft {
  VsdxLine? line;
  VsdxFill? fill;
  VsdxShadow? shadow;
  int lineParent = _minusOne;
  int fillParent = _minusOne;
  int textParent = _minusOne;
  // Text style cells collected while `_isInStyles` (libvisio style sheet Char/Para/TextBlock).
  String? fontFamily;
  VsdLegacyTextEncoding fontEncoding = VsdLegacyTextEncoding.ansi;
  double? fontSizeInches;
  VsdxColor? textColor;
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool smallCaps = false;
  VsdxTextCase textCase = VsdxTextCase.normal;
  VsdxTextPosition textPosition = VsdxTextPosition.normal;
  bool strikethrough = false;
  bool doubleUnderline = false;
  bool doubleStrikethrough = false;
  double fontScale = 1.0;
  bool hideText = false;
  double? marginLeft;
  double? marginRight;
  double? marginTop;
  double? marginBottom;
  VsdxVertAlign? verticalAlign;
  VsdxColor? textBgColor;
  bool? textBgFilled;
  double? defaultTabStop;
  int? textDirection;
  VsdxHorzAlign? paraAlign;
  double? indFirst;
  double? indLeft;
  double? indRight;
  double? spLine;
  double? spBefore;
  double? spAfter;
  int? bullet;
  String? bulletStr;
  String? bulletFont;
  double? bulletFontSize;
  double? textPosAfterBullet;
  int? paraFlags;
  bool hasCharStyle = false;
  bool hasParaStyle = false;
  bool hasTextBlock = false;
}

class _PageDraft {
  _PageDraft(this.id);
  final int id;
  String name = 'Page-1';
  bool isBackgroundPage = false;
  int? backgroundPageId;
  double width = 8.5;
  double height = 11.0;
  /// `pageScale / drawingScale` from PageProps (libvisio `m_scale`).
  double scale = 1.0;
  double pageScale = 1.0;
  double drawingScale = 1.0;
  /// PageProps `drawingScaleUnit` cell type (libvisio `m_defaultDrawingUnit`).
  /// Used when TextField cell type is DrawingUnits (64) / PageUnits (63).
  int drawingScaleUnit = 0;
  double shadowOffsetX = 0.125;
  double shadowOffsetY = -0.125;
  final shapes = <_ShapeDraft>[];
  /// Root ShapeList record ids from the list trailer.
  final shapeOrder = <int>[];
  /// ShapeList record id → actual root shape id from ShapeId records.
  final shapeIds = <int, int>{};
  final layers = <VsdxLayer>[];
  /// Page-scoped NameIDX elementId → display name (shapes / layers).
  final elementNames = <int, String>{};
  /// Page-level Connect rows (glue); filled when ConnectList is understood.
  final connects = <VsdxConnect>[];
}

/// Parses a VisioDocument stream (VSD5 / VSD6 / VSD11) into an editable model.
class VsdBinaryParser {
  VsdBinaryParser(this._docStream);

  final Uint8List _docStream;
  late VsdByteReader _input;
  int _version = 11;

  final _colours = <VsdxColor>[];
  final _styles = <int, _StyleDraft>{};
  final _pages = <_PageDraft>[];
  /// Name2 table: nameId → decoded string (libvisio `m_names`).
  final _names = <int, String>{};
  /// NameIDX: level → (elementId → name) (libvisio `m_namesMapMap`).
  final _namesByLevel = <int, Map<int, String>>{};
  /// FontFace id → family name + legacy code page (libvisio `m_fonts`).
  final _fonts = <int, _VsdFontInfo>{};
  /// stencilPageId → (shapeId → draft)
  final _stencils = <int, Map<int, _ShapeDraft>>{};
  Map<int, _ShapeDraft>? _currentStencilShapes;
  double _stencilShadowOffsetX = 0;
  double _stencilShadowOffsetY = 0;
  _PageDraft? _currentPage;
  _ShapeDraft? _shape;
  bool _isShapeStarted = false;
  bool _isInStyles = false;
  bool _isStencilStarted = false;
  int _currentLevel = 0;
  int _currentShapeLevel = 0;
  int _currentShapeId = _minusOne;
  VsdChunkHeader _header = VsdChunkHeader();
  int _currentStyleId = _minusOne;
  bool _isBackgroundPage = false;

  VsdxDocument parse() {
    _input = VsdByteReader(_docStream);
    _verifyMagic();
    _input.seek(0x1A);
    _version = _input.readU8();
    if (_version != 5 && _version != 6 && _version != 11) {
      throw VsdxFormatException(
        'Unsupported Visio binary version $_version '
        '(supported: 5 = Visio 5, 6 = Visio 2000, 11 = Visio 2002–2010)',
      );
    }

    _input.seek(0x24);
    final trailerPtr = _readPointer(_input);
    final compressed = trailerPtr.compressed;
    final shift = compressed ? 4 : 0;
    _input.seek(trailerPtr.offset);
    final trailerRaw = _input.readBytes(trailerPtr.length);
    final trailerBytes = vsdInflate(trailerRaw, compressed: compressed);
    final trailer = VsdByteReader(trailerBytes);

    // Two passes: styles first, then content (mirrors libvisio).
    _parseDocument(trailer, shift, collectStylesOnly: true);
    _handleLevelChange(0);
    _resetPassState();
    trailer.seek(0);
    _parseDocument(trailer, shift, collectStylesOnly: false);
    _handleLevelChange(0);

    return _buildDocument();
  }

  void _verifyMagic() {
    const magic = 'Visio (TM) Drawing\r\n\x00';
    _input.seek(0);
    final bytes = _input.readBytes(magic.length);
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) {
        throw const VsdxFormatException('Missing VisioDocument magic');
      }
    }
  }

  void _resetPassState() {
    _pages.clear();
    _currentPage = null;
    _currentStencilShapes = null;
    _stencilShadowOffsetX = 0;
    _stencilShadowOffsetY = 0;
    // Keep _stencils across? No — styles pass skips them; content rebuilds.
    _stencils.clear();
    // Preserve name/font tables collected in the styles pass.
    _foreignPartByShapeId.clear();
    _foreignTypeByShapeId.clear();
    _shape = null;
    _isShapeStarted = false;
    _isInStyles = false;
    _isStencilStarted = false;
    _currentLevel = 0;
    _currentShapeLevel = 0;
    _currentShapeId = _minusOne;
    _isBackgroundPage = false;
  }

  void _parseDocument(
    VsdByteReader input,
    int shift, {
    required bool collectStylesOnly,
  }) {
    final visited = <int>{};
    _handleStreams(
      input,
      VsdRecordId.trailerStream,
      shift,
      0,
      visited,
      collectStylesOnly: collectStylesOnly,
    );
  }

  void _handleStreams(
    VsdByteReader input,
    int ptrType,
    int shift,
    int level,
    Set<int> visited, {
    required bool collectStylesOnly,
  }) {
    final ptrList = <int, VsdPointer>{};
    final fontFaces = <int, VsdPointer>{};
    final nameList = <int, VsdPointer>{};
    final nameIdx = <int, VsdPointer>{};
    final pointerOrder = <int>[];

    try {
      final info = _readPointerInfo(input, ptrType, shift);
      var listSize = info.listSize;
      for (var i = 0; i < info.pointerCount; i++) {
        final ptr = _readPointer(input);
        if (ptr.type == 0) continue;
        if (ptr.type == VsdRecordId.fontFaces ||
            ptr.type == VsdRecordId.fontList) {
          fontFaces[i] = ptr;
        } else if (ptr.type == VsdRecordId.nameList2) {
          nameList[i] = ptr;
        } else if (ptr.type == VsdRecordId.nameIdx ||
            ptr.type == VsdRecordId.nameIdx123) {
          nameIdx[i] = ptr;
        } else {
          ptrList[i] = ptr;
        }
      }
      if (listSize <= 1) listSize = 0;
      while (listSize-- > 0) {
        pointerOrder.add(input.readU32());
      }
    } catch (_) {
      ptrList.clear();
      pointerOrder.clear();
    }

    for (final e in nameList.entries) {
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
    for (final e in nameIdx.entries) {
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
    for (final e in fontFaces.entries) {
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
    // Prefer stencils before pages so master shapes exist when pages instantiate.
    final stencilPtrs = <MapEntry<int, VsdPointer>>[];
    final pagePtrs = <MapEntry<int, VsdPointer>>[];
    final otherPtrs = <MapEntry<int, VsdPointer>>[];
    for (final e in ptrList.entries) {
      if (e.value.type == VsdRecordId.stencils) {
        stencilPtrs.add(e);
      } else if (e.value.type == VsdRecordId.pages) {
        pagePtrs.add(e);
      } else {
        otherPtrs.add(e);
      }
    }
    if (pointerOrder.isNotEmpty) {
      for (final j in pointerOrder) {
        final ptr = ptrList.remove(j);
        if (ptr != null) {
          _handleStream(ptr, j, level + 1, visited,
              collectStylesOnly: collectStylesOnly);
        }
      }
    }
    for (final e in [...stencilPtrs, ...otherPtrs, ...pagePtrs]) {
      if (!ptrList.containsKey(e.key)) continue;
      ptrList.remove(e.key);
      _handleStream(e.value, e.key, level + 1, visited,
          collectStylesOnly: collectStylesOnly);
    }
  }

  void _handleStream(
    VsdPointer ptr,
    int idx,
    int level,
    Set<int> visited, {
    required bool collectStylesOnly,
  }) {
    _header = VsdChunkHeader()
      ..level = level
      ..id = idx
      ..chunkType = ptr.type;
    _handleLevelChange(level);

    // Background pages are first-class Visio pages. libvisio retains them and
    // composites them under foreground pages through the Page record's
    // backgroundPageID, so do not discard their streams here.
    if (ptr.type == VsdRecordId.page) {
      if (collectStylesOnly) return;
      _isBackgroundPage = (ptr.format & 0x1) == 0;
      final resolved = _nameFromId(idx, level + 1);
      // Reject pure-numeric "names" (often mis-mapped NameIDX entries).
      final pageName =
          (resolved != null && !RegExp(r'^\d+$').hasMatch(resolved))
              ? resolved
              : 'Page-${_pages.length + 1}';
      _currentPage = _PageDraft(idx)
        ..name = pageName
        ..isBackgroundPage = _isBackgroundPage;
      _pages.add(_currentPage!);
    }
    if (ptr.type == VsdRecordId.styles) {
      _isInStyles = true;
    }
    if (ptr.type == VsdRecordId.stencils) {
      if (collectStylesOnly) return;
      if (_stencils.isNotEmpty) return;
      _isStencilStarted = true;
    }
    if (ptr.type == VsdRecordId.stencilPage) {
      if (collectStylesOnly || !_isStencilStarted) return;
      _currentStencilShapes = <int, _ShapeDraft>{};
      _stencilShadowOffsetX = 0;
      _stencilShadowOffsetY = 0;
      _stencils[idx] = _currentStencilShapes!;
    }
    if (ptr.type == VsdRecordId.shapeGroup ||
        ptr.type == VsdRecordId.shapeShape ||
        ptr.type == VsdRecordId.shapeForeign) {
      if (!collectStylesOnly) _currentShapeId = idx;
    }

    _input.seek(ptr.offset);
    final raw = _input.readBytes(ptr.length);
    final streamBytes = vsdInflate(raw, compressed: ptr.compressed);
    final stream = VsdByteReader(streamBytes);
    _header.dataLength = streamBytes.length;
    final shift = ptr.compressed ? 4 : 0;
    final fmtHi = ptr.format >> 4;

    if (fmtHi == 0x4 || fmtHi == 0x5 || fmtHi == 0x0) {
      _handleBlob(stream, shift, level + 1, collectStylesOnly: collectStylesOnly);
      if (fmtHi == 0x5 && ptr.type != VsdRecordId.colors) {
        if (visited.add(ptr.offset)) {
          try {
            _handleStreams(
              stream,
              ptr.type,
              shift,
              level + 1,
              visited,
              collectStylesOnly: collectStylesOnly,
            );
          } finally {
            visited.remove(ptr.offset);
          }
        }
      }
    } else if (fmtHi == 0xd || fmtHi == 0xc || fmtHi == 0x8) {
      _handleChunks(stream, level + 1, collectStylesOnly: collectStylesOnly);
    }

    if (ptr.type == VsdRecordId.styles) {
      _handleLevelChange(0);
      _isInStyles = false;
    }
    if (ptr.type == VsdRecordId.page) {
      _handleLevelChange(0);
      _currentPage = null;
      _isBackgroundPage = false;
    }
    if (ptr.type == VsdRecordId.stencilPage) {
      _handleLevelChange(0);
      _currentStencilShapes = null;
    }
    if (ptr.type == VsdRecordId.stencils) {
      _handleLevelChange(0);
      _isStencilStarted = false;
    }
    if ((ptr.type == VsdRecordId.shapeGroup ||
            ptr.type == VsdRecordId.shapeShape ||
            ptr.type == VsdRecordId.shapeForeign) &&
        _isStencilStarted) {
      _handleLevelChange(0);
    }
  }

  void _handleBlob(
    VsdByteReader input,
    int shift,
    int level, {
    required bool collectStylesOnly,
  }) {
    try {
      _header.level = level;
      input.seek(shift);
      _header.dataLength -= shift;
      _handleLevelChange(_header.level);
      _handleChunk(input, collectStylesOnly: collectStylesOnly);
    } catch (_) {}
  }

  void _handleChunks(
    VsdByteReader input,
    int level, {
    required bool collectStylesOnly,
  }) {
    while (!input.isEnd) {
      if (!_readChunkHeader(input)) return;
      _header.level += level;
      final endPos = _header.dataLength + _header.trailer + input.offset;
      _handleLevelChange(_header.level);
      _handleChunk(input, collectStylesOnly: collectStylesOnly);
      if (endPos > input.length) return;
      input.seek(endPos);
    }
  }

  bool _readChunkHeader(VsdByteReader input) {
    var tmp = 0;
    while (!input.isEnd && tmp == 0) {
      tmp = input.readU8();
    }
    if (input.isEnd) return false;
    input.seek(input.offset - 1);

    if (_version == 5) {
      // Visio 5: typed ints are int16; trailer always 0 (libvisio VSD5Parser).
      _header.chunkType = _getUInt(input);
      _header.id = _getUInt(input);
      _header.level = input.readU8();
      _header.unknown = input.readU8();
      _header.trailer = 0;
      _header.list = _getUInt(input);
      _header.dataLength = input.readU32();
      return true;
    }

    _header.chunkType = input.readU32();
    _header.id = input.readU32();
    _header.list = input.readU32();
    _header.trailer = 0;

    if (_version == 6) {
      // VSD6 trailer rules (algorithm reference: libvisio VSD6Parser).
      if (_header.list != 0 ||
          (_header.chunkType >= 0x64 && _header.chunkType <= 0x76) ||
          _header.chunkType == 0x2c ||
          _header.chunkType == 0xd) {
        _header.trailer += 8;
      }
      _header.dataLength = input.readU32();
      _header.level = input.readU16();
      _header.unknown = input.readU8();
      if (_header.chunkType == 0x1f || _header.chunkType == 0xc9) {
        _header.trailer = 0;
      }
      return true;
    }

    // VSD11
    if (_header.list != 0 ||
        _header.chunkType == 0x71 ||
        _header.chunkType == 0x70 ||
        _header.chunkType == 0x6b ||
        _header.chunkType == 0x6a ||
        _header.chunkType == 0x69 ||
        _header.chunkType == 0x66 ||
        _header.chunkType == 0x65 ||
        _header.chunkType == 0x2c) {
      _header.trailer += 8;
    }
    _header.dataLength = input.readU32();
    _header.level = input.readU16();
    _header.unknown = input.readU8();

    if (_header.list != 0 ||
        (_header.level == 2 && _header.unknown == 0x55) ||
        (_header.level == 2 &&
            _header.unknown == 0x54 &&
            _header.chunkType == 0xaa) ||
        (_header.level == 3 &&
            _header.unknown != 0x50 &&
            _header.unknown != 0x54)) {
      _header.trailer += 4;
    }
    const trailerChunks = <int>[
      0x64, 0x65, 0x66, 0x69, 0x6a, 0x6b, 0x6f, 0x71,
      0x92, 0xa9, 0xb4, 0xb6, 0xb9, 0xc7,
    ];
    for (final t in trailerChunks) {
      if (_header.chunkType == t &&
          _header.trailer != 12 &&
          _header.trailer != 4) {
        _header.trailer += 4;
        break;
      }
    }
    if (_header.chunkType == 0x1f ||
        _header.chunkType == 0xc9 ||
        _header.chunkType == 0x2d ||
        _header.chunkType == 0xd1) {
      _header.trailer = 0;
    }
    return true;
  }

  VsdPointer _readPointer(VsdByteReader input) =>
      _version == 5 ? input.readPointerVsd5() : input.readPointer();

  /// Positions [input] at the first pointer and returns list/pointer counts.
  ({int listSize, int pointerCount}) _readPointerInfo(
    VsdByteReader input,
    int ptrType,
    int shift,
  ) {
    if (_version == 5) {
      // Algorithm reference: libvisio VSD5Parser::readPointerInfo.
      switch (ptrType) {
        case VsdRecordId.trailerStream:
          input.seek(shift + 0x82);
        case VsdRecordId.page:
          input.seek(shift + 0x42);
        case VsdRecordId.fontList:
          input.seek(shift + 0x2e);
        case VsdRecordId.styles:
          input.seek(shift + 0x12);
        case VsdRecordId.stencils:
        case VsdRecordId.shapeForeign:
          input.seek(shift + 0x1e);
        case VsdRecordId.stencilPage:
          input.seek(shift + 0x36);
        default:
          if (ptrType > 0x45) {
            input.seek(shift + 0x1e);
          } else {
            input.seek(shift + 0xa);
          }
      }
      return (listSize: 0, pointerCount: input.readS16());
    }

    input.seek(shift);
    final offset = input.readU32();
    input.seek(offset + shift - 4);
    final listSize = input.readU32();
    final pointerCount = input.readS32();
    input.skip(4);
    return (listSize: listSize, pointerCount: pointerCount);
  }

  /// Visio 5 typed integers are signed 16-bit (libvisio `VSD5Parser::getUInt`).
  int _getUInt(VsdByteReader input) {
    if (_version == 5) return vsdV5UnsignedInt(input.readS16());
    return input.readU32();
  }

  /// VSD5 packs child cells at the end of list chunks (libvisio handleChunkRecords).
  void _handleChunkRecords(
    VsdByteReader input, {
    required bool collectStylesOnly,
  }) {
    final startPosition = input.offset;
    final endPosition = input.offset + _header.dataLength;
    if (endPosition > input.length || endPosition - 4 < startPosition) return;
    input.seek(endPosition - 4);
    final numRecords = input.readU16();
    final headerPosition = endPosition - 4 * (numRecords + 1);
    if (headerPosition <= startPosition) return;
    var endOffset = input.readU16();
    if (endOffset > headerPosition - startPosition) {
      endOffset = headerPosition - startPosition;
    }
    final records = <int, VsdChunkHeader>{};
    input.seek(headerPosition);
    for (var i = 0; i < numRecords; i++) {
      final chunkType = input.readU16();
      final offset = input.readU16();
      var tmpStart = offset;
      while (tmpStart % 4 != 0) {
        tmpStart++;
      }
      if (tmpStart < endOffset) {
        records[tmpStart] = VsdChunkHeader(
          chunkType: chunkType,
          dataLength: endOffset - tmpStart,
          level: _header.level + 1,
        );
        endOffset = offset;
      }
    }
    var seq = 0;
    final sorted = records.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in sorted) {
      _header = e.value..id = seq++;
      input.seek(startPosition + e.key);
      _handleChunk(input, collectStylesOnly: collectStylesOnly);
    }
  }

  void _handleChunk(VsdByteReader input, {required bool collectStylesOnly}) {
    if (collectStylesOnly) {
      switch (_header.chunkType) {
        case VsdRecordId.colors:
          _readColours(input);
          return;
        case VsdRecordId.styleSheet:
          _readStyleSheet(input);
          return;
        case VsdRecordId.line:
          _readLine(input);
          return;
        case VsdRecordId.fillAndShadow:
          _readFillAndShadow(input);
          return;
        case VsdRecordId.name2:
          _readName2(input);
          return;
        case VsdRecordId.nameList2:
          if (_version == 5) {
            _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
          } else {
            _names.clear();
          }
          return;
        case VsdRecordId.nameIdx:
          _readNameIdx(input);
          return;
        case VsdRecordId.nameIdx123:
          _readNameIdx123(input);
          return;
        case VsdRecordId.fontFace:
          _readFontFace(input);
          return;
        case VsdRecordId.fontIx:
          _readFontIx(input);
          return;
        case VsdRecordId.charIx:
          _readCharIx(input);
          return;
        case VsdRecordId.paraIx:
          _readParaIx(input);
          return;
        case VsdRecordId.textBlock:
          _readTextBlock(input);
          return;
        default:
          return;
      }
    }

    switch (_header.chunkType) {
      case VsdRecordId.shapeGroup:
      case VsdRecordId.shapeShape:
      case VsdRecordId.shapeForeign:
        _readShape(input);
      case VsdRecordId.xformData:
        _readXFormData(input);
      case VsdRecordId.xform1d:
        _readXForm1D(input);
      case VsdRecordId.textXform:
        _readTextXForm(input);
      case VsdRecordId.line:
        _readLine(input);
      case VsdRecordId.fillAndShadow:
        _readFillAndShadow(input);
      case VsdRecordId.geomList:
        _readGeomList(input);
      case VsdRecordId.geometry:
        _readGeometry(input);
      case VsdRecordId.moveTo:
        _readMoveTo(input);
      case VsdRecordId.lineTo:
        _readLineTo(input);
      case VsdRecordId.arcTo:
        _readArcTo(input);
      case VsdRecordId.ellipse:
        _readEllipse(input);
      case VsdRecordId.ellipticalArcTo:
        _readEllipticalArcTo(input);
      case VsdRecordId.polylineTo:
        _readPolylineTo(input);
      case VsdRecordId.nurbsTo:
        _readNurbsTo(input);
      case VsdRecordId.infiniteLine:
        _readInfiniteLine(input);
      case VsdRecordId.splineStart:
        _readSplineStart(input);
      case VsdRecordId.splineKnot:
        _readSplineKnot(input);
      case VsdRecordId.shapeData:
        _readShapeData(input);
      case VsdRecordId.textField:
        _readTextField(input);
      case VsdRecordId.misc:
        _readMisc(input);
      case VsdRecordId.event:
        if (!collectStylesOnly) _readEvent(input);
      case VsdRecordId.layer:
        _readLayer(input);
      case VsdRecordId.layerMembership:
        _readLayerMem(input);
      case VsdRecordId.name2:
        _readName2(input);
      case VsdRecordId.name:
        _readName(input);
      case VsdRecordId.nameIdx:
        _readNameIdx(input);
      case VsdRecordId.nameIdx123:
        _readNameIdx123(input);
      case VsdRecordId.fontFace:
        _readFontFace(input);
      case VsdRecordId.fontIx:
        _readFontIx(input);
      case VsdRecordId.textBlock:
        _readTextBlock(input);
      case VsdRecordId.page:
        if (!collectStylesOnly) _readPage(input);
      case VsdRecordId.pageProps:
        _readPageProps(input);
      case VsdRecordId.text:
        _readText(input);
      case VsdRecordId.charIx:
        _readCharIx(input);
      case VsdRecordId.paraIx:
        _readParaIx(input);
      case VsdRecordId.colors:
        _readColours(input);
      case VsdRecordId.styleSheet:
        _readStyleSheet(input);
      case VsdRecordId.shapeList:
        _readShapeList(input);
      case VsdRecordId.nameList:
        // libvisio `readNameList` — clear shape-local names before new Name rows.
        if (!collectStylesOnly) _shape?.localNames.clear();
      case VsdRecordId.nameList2:
        if (_version == 5) {
          // VSD5 embeds Name2 records in the list payload rather than exposing
          // them as child pointer streams.
          _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
        } else {
          // libvisio `readNameList2` scopes subsequent Name2/NameIDX records.
          _names.clear();
        }
      case VsdRecordId.charList:
        if (_version == 5) {
          _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
        } else if (!collectStylesOnly) {
          _readListOrder(input, into: _shape?.charOrder);
        }
      case VsdRecordId.paraList:
        if (_version == 5) {
          _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
        } else if (!collectStylesOnly) {
          _readListOrder(input, into: _shape?.paraOrder);
        }
      case VsdRecordId.fieldList:
        if (_version == 5) {
          _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
        } else if (!collectStylesOnly) {
          _readListOrder(input, into: _shape?.fieldOrder);
        }
      case VsdRecordId.propList:
        if (_version == 5) {
          _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
        }
      case VsdRecordId.tabsDataList:
        if (_version == 5) {
          _handleChunkRecords(input, collectStylesOnly: collectStylesOnly);
        } else if (!collectStylesOnly) {
          _readListOrder(input, into: _shape?.tabOrder);
        }
      case VsdRecordId.tabsData1:
      case VsdRecordId.tabsData2:
      case VsdRecordId.tabsData3:
      case VsdRecordId.tabsData4:
        if (!collectStylesOnly) _readTabsData(input);
      case VsdRecordId.shapeId:
        _readShapeId(input);
      case VsdRecordId.foreignDataType:
        _readForeignDataType(input);
      case VsdRecordId.foreignData:
        _readForeignData(input);
      case VsdRecordId.oleList:
        // libvisio `readOLEList` is empty; collector clears the foreign buffer
        // before subsequent `oleData` chunks append.
        if (!collectStylesOnly) _shape?.foreignBytes = Uint8List(0);
      case VsdRecordId.oleData:
        if (!collectStylesOnly) _readOleData(input);
      case VsdRecordId.pageSheet:
        _currentShapeLevel = _header.level;
      case VsdRecordId.cPntsList:
        // Trailer id order for Connection rows (like CharList).
        if (_version != 5) {
          _readListOrder(input, into: _shape?.connectionOrder);
        }
      case VsdRecordId.connectionPoints:
      case VsdRecordId.connectionPointsAlt:
        _readConnectionPoints(input);
      case VsdRecordId.ctrlList:
        if (_version != 5) {
          _readListOrder(input, into: _shape?.controlOrder);
        }
      case VsdRecordId.control:
      case VsdRecordId.controlAlt:
        if (!collectStylesOnly) _readControl(input);
      case VsdRecordId.custPropsList:
        if (_version != 5) {
          _readListOrder(input, into: _shape?.propOrder);
        }
      case VsdRecordId.customProps:
        if (!collectStylesOnly) _readCustomProps(input);
      case VsdRecordId.scratchList:
        if (_version != 5) {
          _readListOrder(input, into: _shape?.scratchOrder);
        }
      case VsdRecordId.scratch:
        if (!collectStylesOnly) _readScratch(input);
      case VsdRecordId.userDefinedCells:
        if (!collectStylesOnly) _readUserDefinedCell(input);
      case VsdRecordId.actIdList:
        if (_version != 5) {
          _readListOrder(input, into: _shape?.actionOrder);
        }
      case VsdRecordId.actId:
        if (!collectStylesOnly) _readActId(input);
      case VsdRecordId.protection:
        if (!collectStylesOnly) _readProtection(input);
      case VsdRecordId.group:
        if (!collectStylesOnly) _readGroup(input);
      case VsdRecordId.hyperLnkList:
        if (_version != 5) {
          _readListOrder(input, into: _shape?.hyperlinkOrder);
        }
      case VsdRecordId.hyperlink:
        if (!collectStylesOnly) _readHyperlink(input);
      case VsdRecordId.connectList:
        _readConnectList(input);
      default:
        break;
    }
  }

  void _handleLevelChange(int level) {
    if (level == _currentLevel) return;
    if (level <= _currentShapeLevel) {
      _flushShape();
      _shape = null;
      _isShapeStarted = false;
    }
    _currentLevel = level;
  }

  void _flushShape() {
    if (!_isShapeStarted || _shape == null) return;
    final d = _shape!;

    if (_isStencilStarted) {
      // ShapeData can follow its geometry row in a stencil stream.
      _resolvePendingShapeData(d);
      _resolveStringFields(d, null);
      final bucket = _currentStencilShapes;
      if (bucket != null) {
        bucket[d.id] = d;
      }
      return;
    }

    if (_currentPage == null) return;
    final master = _applyMasterInheritance(d);
    _resolveStringFields(d, master);
    d.shapeName ??= _currentPage!.elementNames[d.id];
    d.line ??= _resolveLineStyle(d.lineStyleId);
    final fillStyle = _resolveFillStyle(d.fillStyleId);
    d.fill ??= fillStyle.$1;
    d.shadow ??= fillStyle.$2;
    if (d.shadow case final shadow?) {
      // VSDContentCollector substitutes PageProps per axis when a resolved
      // shape, master, or FillStyle shadow offset is exactly zero.
      d.shadow = shadow.copyWith(
        offsetXInches: libvisioEffectiveShadowOffset(
          shadow.offsetXInches,
          _currentPage!.shadowOffsetX,
        ),
        offsetYInches: libvisioEffectiveShadowOffset(
          shadow.offsetYInches,
          _currentPage!.shadowOffsetY,
        ),
      );
    }
    _applyTextStyle(d);
    _resolvePendingShapeData(d, master: master);
    _dedupeConnectionPoints(d);
    // Drop GeomList shells that never received path commands (common on
    // ForeignData picture frames — trailer may list child ids with no rows).
    d.geometries.removeWhere((g) => g.byId.isEmpty);
    // Line fallback for 1D connectors without geometry.
    if (d.geometries.isEmpty && d.is1D) {
      final x0 = 0.0;
      final y0 = d.height / 2;
      final x1 = d.width;
      final y1 = d.height / 2;
      final g = _GeomBuilder()
        ..byId[0] = MoveTo(x0, y0)
        ..byId[1] = LineTo(x1, y1)
        ..order.addAll([0, 1]);
      d.geometries.add(g);
    }
    // A resolved master with no geometry is a group/text container. libvisio
    // does not invent a path for it; doing so paints a spurious filled box
    // behind the master's children. Keep the resilience fallback only for a
    // shape whose geometry could not be resolved from any master.
    if (d.geometries.isEmpty && !d.is1D && master == null) {
      final g = _GeomBuilder()
        ..byId[0] = const MoveTo(0, 0)
        ..byId[1] = LineTo(d.width, 0)
        ..byId[2] = LineTo(d.width, d.height)
        ..byId[3] = LineTo(0, d.height)
        ..byId[4] = const LineTo(0, 0)
        ..order.addAll([0, 1, 2, 3, 4]);
      // Picture frames: no stroke fill from geometry — painter draws the image.
      if (d.foreignBytes != null) {
        g.noLine = true;
        g.noFill = true;
      }
      d.geometries.add(g);
    }
    _currentPage!.shapes.add(d);
  }

  void _resolvePendingShapeData(_ShapeDraft d, {_ShapeDraft? master}) {
    for (final pending in d.pendingPolylineData) {
      if (pending.geometryIndex < 0 ||
          pending.geometryIndex >= d.geometries.length) {
        continue;
      }
      final masterGeom = master != null &&
              pending.geometryIndex < master.geometries.length
          ? master.geometries[pending.geometryIndex]
          : null;
      final blob = vsdResolveShapeDataReference(
        dataId: pending.dataId,
        localData: d.polylineData,
        masterData: master?.polylineData,
        masterDataId: masterGeom?.polylineDataIds[pending.rowId],
      );
      if (blob == null || blob.points.isEmpty) continue;
      d.geometries[pending.geometryIndex].byId[pending.rowId] = PolylineTo(
        x: pending.x,
        y: pending.y,
        vertices: blob.points,
        vertsRelative: blob.xRel,
        vertsYRelative: blob.yRel,
      );
    }
    d.pendingPolylineData.clear();
    for (final pending in d.pendingNurbsData) {
      if (pending.geometryIndex < 0 ||
          pending.geometryIndex >= d.geometries.length) {
        continue;
      }
      final masterGeom = master != null &&
              pending.geometryIndex < master.geometries.length
          ? master.geometries[pending.geometryIndex]
          : null;
      final n = vsdResolveShapeDataReference(
        dataId: pending.dataId,
        localData: d.nurbsData,
        masterData: master?.nurbsData,
        masterDataId: masterGeom?.nurbsDataIds[pending.rowId],
      );
      if (n == null || n.cps.isEmpty) continue;
      final assembled = vsdAssembleNurbsShapeData(
        dataKnots: n.knots,
        dataWeights: n.weights,
        firstKnot: pending.knotPrev,
        secondLastKnot: pending.knot,
        lastKnot: n.lastKnot,
        firstWeight: pending.weightPrev,
        lastWeight: pending.weight,
      );
      d.geometries[pending.geometryIndex].byId[pending.rowId] = NurbsTo(
        x: pending.x,
        y: pending.y,
        controlPoints: n.cps,
        knots: assembled.knots,
        weights: assembled.weights,
        degree: n.degree,
        cpRelative: n.xRel,
        cpYRelative: n.yRel,
      );
    }
    d.pendingNurbsData.clear();
  }

  void _dedupeConnectionPoints(_ShapeDraft d) {
    if (d.connectionPoints.length < 2) return;
    final seen = <String>{};
    d.connectionPoints.retainWhere((c) {
      final key =
          '${c.x.toStringAsFixed(6)},${c.y.toStringAsFixed(6)},${c.type}';
      return seen.add(key);
    });
  }

  /// Apply CharList / ParaList / FieldList / TabsDataList trailer order
  /// (libvisio `setElementsOrder`). Encounter order is used when no trailer.
  void _applyListOrders(_ShapeDraft d) {
    if (d.charOrder.isNotEmpty && d.charRuns.isNotEmpty) {
      final ordered =
          vsdReorderById(List.of(d.charRuns), d.charOrder, (c) => c.id);
      d.charRuns
        ..clear()
        ..addAll(ordered);
    }
    if (d.paraOrder.isNotEmpty && d.paraRuns.isNotEmpty) {
      final ordered =
          vsdReorderById(List.of(d.paraRuns), d.paraOrder, (p) => p.id);
      d.paraRuns
        ..clear()
        ..addAll(ordered);
    }
    if (d.tabOrder.isNotEmpty && d.tabRuns.isNotEmpty) {
      final ordered =
          vsdReorderById(List.of(d.tabRuns), d.tabOrder, (t) => t.id);
      d.tabRuns
        ..clear()
        ..addAll(ordered);
    }
    if (d.connectionOrder.isNotEmpty && d.connectionPoints.isNotEmpty) {
      final ordered = vsdReorderById(
        List.of(d.connectionPoints),
        d.connectionOrder,
        (c) => c.id,
      );
      d.connectionPoints
        ..clear()
        ..addAll(ordered);
    }
    if (d.controlOrder.isNotEmpty && d.controls.isNotEmpty) {
      final ordered = vsdReorderById(
        List.of(d.controls),
        d.controlOrder,
        (c) => c.id,
      );
      d.controls
        ..clear()
        ..addAll(ordered);
    }
    if (d.propOrder.isNotEmpty && d.userProperties.isNotEmpty) {
      final ordered = vsdReorderById(
        List.of(d.userProperties),
        d.propOrder,
        (p) => p.id,
      );
      d.userProperties
        ..clear()
        ..addAll(ordered);
    }
    if (d.scratchOrder.isNotEmpty && d.scratchRows.isNotEmpty) {
      final ordered = vsdReorderById(
        List.of(d.scratchRows),
        d.scratchOrder,
        (r) => r.id,
      );
      d.scratchRows
        ..clear()
        ..addAll(ordered);
    }
    if (d.actionOrder.isNotEmpty && d.actions.isNotEmpty) {
      final ordered = vsdReorderById(
        List.of(d.actions),
        d.actionOrder,
        (a) => a.id,
      );
      d.actions
        ..clear()
        ..addAll(ordered);
    }
    if (d.hyperlinkOrder.isNotEmpty && d.hyperlinks.isNotEmpty) {
      final ordered = vsdReorderById(
        List.of(d.hyperlinks),
        d.hyperlinkOrder,
        (h) => h.id,
      );
      d.hyperlinks
        ..clear()
        ..addAll(ordered);
    }
    if (d.fieldOrder.isNotEmpty &&
        d.fieldDisplays.isNotEmpty &&
        d.fieldIds.length == d.fieldDisplays.length) {
      final entries = <({
        int id,
        String text,
        ({double number, int cellType, int format, String? customFormat})? raw,
        ({int nameId, int format, int formatStringId})? stringRef,
      })>[
        for (var i = 0; i < d.fieldDisplays.length; i++)
          (
            id: d.fieldIds[i],
            text: d.fieldDisplays[i],
            raw: i < d.fieldRaw.length ? d.fieldRaw[i] : null,
            stringRef: i < d.fieldStringRefs.length
                ? d.fieldStringRefs[i]
                : null,
          ),
      ];
      final ordered = vsdReorderById(entries, d.fieldOrder, (e) => e.id);
      d.fieldDisplays
        ..clear()
        ..addAll([for (final e in ordered) e.text]);
      d.fieldIds
        ..clear()
        ..addAll([for (final e in ordered) e.id]);
      if (d.fieldRaw.isNotEmpty) {
        d.fieldRaw
          ..clear()
          ..addAll([for (final e in ordered) e.raw]);
      }
      if (d.fieldStringRefs.isNotEmpty) {
        d.fieldStringRefs
          ..clear()
          ..addAll([for (final e in ordered) e.stringRef]);
      }
    }
  }

  /// Convert binary TextField chunks to editable VSDX Field rows.
  ///
  /// VSD stores the definition in a FieldList and places a U+FFFC/0x1e
  /// marker in the text stream. The binary format does not expose a VSDX
  /// formula string, so retain its cached display, picture and list id.
  List<VsdxFieldRow> _buildFieldRows(_ShapeDraft d) {
    final rows = <VsdxFieldRow>[];
    for (var i = 0; i < d.fieldDisplays.length; i++) {
      final raw = i < d.fieldRaw.length ? d.fieldRaw[i] : null;
      String? format;
      if (raw != null) {
        if (raw.customFormat != null && raw.customFormat!.isNotEmpty) {
          format = raw.customFormat;
        } else if (raw.format != 0xffff) {
          format = 'esc(${raw.format})';
        }
      }
      rows.add(VsdxFieldRow(
        ix: i < d.fieldIds.length ? d.fieldIds[i] : i,
        value: d.fieldDisplays[i],
        format: format,
      ));
    }
    return List<VsdxFieldRow>.unmodifiable(rows);
  }

  int _fieldIx(_ShapeDraft d, int index) =>
      index < d.fieldIds.length ? d.fieldIds[index] : index;

  ({String text, List<VsdxFieldSpan> spans}) _expandFieldMarkers(
    _ShapeDraft d,
    String rawText,
  ) {
    final out = StringBuffer();
    final spans = <VsdxFieldSpan>[];
    var fieldIndex = 0;
    for (var i = 0; i < rawText.length; i++) {
      final cu = rawText.codeUnitAt(i);
      if (cu != 0xfffc && cu != 0x1e) {
        out.writeCharCode(cu);
        continue;
      }
      if (fieldIndex >= d.fieldDisplays.length) continue;
      final display = d.fieldDisplays[fieldIndex];
      final start = out.length;
      out.write(display);
      spans.add(VsdxFieldSpan(
        start: start,
        length: display.length,
        ix: _fieldIx(d, fieldIndex),
      ));
      fieldIndex++;
    }
    return (text: out.toString(), spans: List.unmodifiable(spans));
  }

  ({String text, List<VsdxFieldSpan> spans}) _trimFieldExpansion(
    String text,
    List<VsdxFieldSpan> spans,
  ) {
    final trimmedLeft = text.trimLeft();
    final leading = text.length - trimmedLeft.length;
    final trimmed = trimmedLeft.trimRight();
    final end = leading + trimmed.length;
    final kept = <VsdxFieldSpan>[];
    for (final span in spans) {
      final spanEnd = span.start + span.length;
      if (span.length == 0) {
        if (span.start >= leading && span.start <= end) {
          kept.add(VsdxFieldSpan(
            start: span.start - leading,
            length: 0,
            ix: span.ix,
          ));
        }
        continue;
      }
      final clippedStart = span.start < leading ? leading : span.start;
      final clippedEnd = spanEnd > end ? end : spanEnd;
      if (clippedStart < clippedEnd) {
        kept.add(VsdxFieldSpan(
          start: clippedStart - leading,
          length: clippedEnd - clippedStart,
          ix: span.ix,
        ));
      }
    }
    return (text: trimmed, spans: List.unmodifiable(kept));
  }

  /// Re-apply numeric field formatting with the page's DrawingUnits default
  /// (libvisio `getString(..., m_defaultDrawingUnit)`). Needed because
  /// TextField chunks may be read before PageProps sets [drawingScaleUnit].
  void _reformatNumericFields(_ShapeDraft d, {int defaultDrawingUnit = 0}) {
    if (d.fieldRaw.isEmpty) return;
    for (var i = 0; i < d.fieldRaw.length && i < d.fieldDisplays.length; i++) {
      final raw = d.fieldRaw[i];
      if (raw == null) continue;
      d.fieldDisplays[i] = _formatNumericField(
        raw.number,
        raw.cellType,
        raw.format,
        raw.customFormat,
        defaultDrawingUnit,
      );
    }
  }

  /// VSD5 text encodes the numeric format after the field marker as
  /// `0x1E` + spaces + `(formatId + 0x20)`. Apply that format and strip the
  /// encoding bytes (libvisio VSD5 leaves format Unknown).
  void _finalizeVsd5FieldFormats(
    _ShapeDraft d, {
    int defaultDrawingUnit = 0,
  }) {
    if (_version != 5) return;
    final text = d.text;
    if (text == null || text.isEmpty || d.fieldDisplays.isEmpty) return;
    final out = StringBuffer();
    var fi = 0;
    for (var i = 0; i < text.length; i++) {
      final cu = text.codeUnitAt(i);
      if (cu == 0x1E || cu == 0xFFFC) {
        out.writeCharCode(cu);
        var j = i + 1;
        while (j < text.length && text.codeUnitAt(j) == 0x20) {
          j++;
        }
        if (j < text.length) {
          final next = text.codeUnitAt(j);
          // Non-space printable → formatId + 0x20 (e.g. '%' → 5).
          if (next > 0x20 && next <= 0x7E) {
            final fmt = next - 0x20;
            if (fi < d.fieldRaw.length && d.fieldRaw[fi] != null) {
              final raw = d.fieldRaw[fi]!;
              d.fieldRaw[fi] = (
                number: raw.number,
                cellType: raw.cellType,
                format: fmt,
                customFormat: raw.customFormat,
              );
              d.fieldDisplays[fi] = _formatNumericField(
                raw.number,
                raw.cellType,
                fmt,
                raw.customFormat,
                defaultDrawingUnit,
              );
            }
            i = j; // skip spaces + format byte
          }
        }
        fi++;
      } else {
        out.writeCharCode(cu);
      }
    }
    d.text = out.toString();
  }

  _ShapeDraft? _applyMasterInheritance(_ShapeDraft d) {
    if (d.masterPage == _minusOne) return null;
    final page = _stencils[d.masterPage];
    if (page == null || page.isEmpty) return null;
    _ShapeDraft? master;
    if (d.masterShape != _minusOne) {
      master = page[d.masterShape];
    }
    master ??= page.values.first;
    if (d.geometries.isEmpty && master.geometries.isNotEmpty) {
      for (final g in master.geometries) {
        final ng = _GeomBuilder()
          ..noFill = g.noFill
          ..noLine = g.noLine
          ..noShow = g.noShow
          ..order.addAll(g.order)
          ..byId.addAll(g.byId)
          ..polylineDataIds.addAll(g.polylineDataIds)
          ..nurbsDataIds.addAll(g.nurbsDataIds);
        d.geometries.add(ng);
      }
    }
    // libvisio seeds a master instance with the stencil XForm before applying
    // an optional local XFormData record. Preserve that distinction so an
    // omitted local record inherits instead of falling back to a 1x1 box.
    if (!d.hasXFormData) {
      d.pinX = master.pinX;
      d.pinY = master.pinY;
      d.width = master.width;
      d.height = master.height;
      d.locPinX = master.locPinX;
      d.locPinY = master.locPinY;
      d.angle = master.angle;
      d.flipX = master.flipX;
      d.flipY = master.flipY;
    }
    if (d.foreignBytes == null && master.foreignBytes != null) {
      d.foreignBytes = Uint8List.fromList(master.foreignBytes!);
      d.foreignType = master.foreignType;
      d.foreignFormat = master.foreignFormat;
      d.imgOffsetX = master.imgOffsetX;
      d.imgOffsetY = master.imgOffsetY;
      d.imgWidth = master.imgWidth;
      d.imgHeight = master.imgHeight;
    }
    d.line ??= master.line;
    d.fill ??= master.fill;
    d.shadow ??= master.shadow;
    d.text ??= master.text;
    d.legacyTextBytes ??= master.legacyTextBytes;
    d.fontSizeInches ??= master.fontSizeInches;
    d.fontFamily ??= master.fontFamily;
    if (d.fontEncoding == VsdLegacyTextEncoding.ansi) {
      d.fontEncoding = master.fontEncoding;
    }
    d.textColor ??= master.textColor;
    d.shapeName ??= master.shapeName;
    d.txtPinX ??= master.txtPinX;
    d.txtPinY ??= master.txtPinY;
    d.txtWidth ??= master.txtWidth;
    d.txtHeight ??= master.txtHeight;
    d.txtLocPinX ??= master.txtLocPinX;
    d.txtLocPinY ??= master.txtLocPinY;
    d.txtAngle ??= master.txtAngle;
    d.marginLeft ??= master.marginLeft;
    d.marginRight ??= master.marginRight;
    d.marginTop ??= master.marginTop;
    d.marginBottom ??= master.marginBottom;
    d.verticalAlign ??= master.verticalAlign;
    // TextBkgnd: explicit transparent (bgIdx 0/0xff) must not inherit a
    // filled colour from the stencil (libvisio isTextBkgndFilled).
    if (d.textBgFilled == null) {
      d.textBgColor ??= master.textBgColor;
      d.textBgFilled = master.textBgFilled;
    } else if (d.textBgFilled == false) {
      d.textBgColor = null;
    }
    d.defaultTabStop ??= master.defaultTabStop;
    d.textDirection ??= master.textDirection;
    d.paraAlign ??= master.paraAlign;
    d.indFirst ??= master.indFirst;
    d.indLeft ??= master.indLeft;
    d.indRight ??= master.indRight;
    d.spLine ??= master.spLine;
    d.spBefore ??= master.spBefore;
    d.spAfter ??= master.spAfter;
    d.bullet ??= master.bullet;
    d.bulletStr ??= master.bulletStr;
    d.bulletFont ??= master.bulletFont;
    d.bulletFontSize ??= master.bulletFontSize;
    d.textPosAfterBullet ??= master.textPosAfterBullet;
    d.paraFlags ??= master.paraFlags;
    if (!d.bold) d.bold = master.bold;
    if (!d.italic) d.italic = master.italic;
    if (!d.underline) d.underline = master.underline;
    if (!d.smallCaps) d.smallCaps = master.smallCaps;
    if (d.textCase == VsdxTextCase.normal) d.textCase = master.textCase;
    if (d.textPosition == VsdxTextPosition.normal) {
      d.textPosition = master.textPosition;
    }
    if (!d.strikethrough) d.strikethrough = master.strikethrough;
    if (!d.doubleUnderline) d.doubleUnderline = master.doubleUnderline;
    if (!d.doubleStrikethrough) {
      d.doubleStrikethrough = master.doubleStrikethrough;
    }
    if (d.fontScale == 1.0 && master.fontScale != 1.0) {
      d.fontScale = master.fontScale;
    }
    // An explicit Misc record with HideText=false overrides a hidden master.
    if (!d.hasMisc) d.hideText = master.hideText;
    if (d.charRuns.isEmpty && master.charRuns.isNotEmpty) {
      d.charRuns.addAll(master.charRuns);
    }
    if (d.paraRuns.isEmpty && master.paraRuns.isNotEmpty) {
      d.paraRuns.addAll(master.paraRuns);
    }
    // FieldList: inherit stencil formats (libvisio collectNumericField clones
    // stencil element and only overrides value/cellType; format comes from
    // master when the instance block is Unknown).
    _inheritMasterFields(d, master);
    // Only inherit tab sets that actually define stops (empty TabsData is
    // common on masters and would otherwise inflate every instance).
    if (d.tabRuns.isEmpty &&
        master.tabRuns.any((t) => t.stops.isNotEmpty)) {
      d.tabRuns.addAll(master.tabRuns);
    }
    // libvisio does not copy LayerMem from binary stencil shapes; membership
    // belongs to the page instance only.
    if (d.connectionPoints.isEmpty && master.connectionPoints.isNotEmpty) {
      for (final c in master.connectionPoints) {
        d.connectionPoints.add(
          _ConnectionPointDraft()
            ..id = c.id
            ..x = c.x
            ..y = c.y
            ..dirX = c.dirX
            ..dirY = c.dirY
            ..type = c.type,
        );
      }
    }
    if (d.controls.isEmpty && master.controls.isNotEmpty) {
      for (final c in master.controls) {
        d.controls.add(
          _ControlDraft()
            ..id = c.id
            ..x = c.x
            ..y = c.y
            ..dynX = c.dynX
            ..dynY = c.dynY
            ..conX = c.conX
            ..conY = c.conY
            ..canGlue = c.canGlue
            ..prompt = c.prompt
            ..name = c.name,
        );
      }
    }
    if (d.userProperties.isEmpty && master.userProperties.isNotEmpty) {
      for (final p in master.userProperties) {
        d.userProperties.add(
          _UserPropDraft()
            ..id = p.id
            ..name = p.name
            ..label = p.label
            ..value = p.value
            ..prompt = p.prompt
            ..format = p.format
            ..type = p.type,
        );
      }
    } else if (d.userProperties.isNotEmpty &&
        master.userProperties.isNotEmpty) {
      // Instance often overrides Value only; take Label/Prompt/Format from
      // the stencil row with the same id.
      final byId = <int, _UserPropDraft>{
        for (final p in master.userProperties) p.id: p,
      };
      for (final p in d.userProperties) {
        final m = byId[p.id];
        if (m == null) continue;
        p.label ??= m.label;
        p.prompt ??= m.prompt;
        p.format ??= m.format;
        if (p.name == null || p.name!.startsWith('Row')) {
          p.name = m.name ?? p.name;
        }
        if (p.type == 0 && m.type != 0) p.type = m.type;
        p.value ??= m.value;
      }
    }
    if (d.scratchRows.isEmpty && master.scratchRows.isNotEmpty) {
      for (final r in master.scratchRows) {
        d.scratchRows.add(
          _ScratchDraft()
            ..id = r.id
            ..x = r.x
            ..y = r.y
            ..a = r.a
            ..b = r.b
            ..c = r.c
            ..d = r.d,
        );
      }
    }
    if (d.userCells.isEmpty && master.userCells.isNotEmpty) {
      for (final c in master.userCells) {
        d.userCells.add(
          _UserCellDraft()
            ..id = c.id
            ..name = c.name
            ..value = c.value
            ..prompt = c.prompt,
        );
      }
    } else if (d.userCells.isNotEmpty && master.userCells.isNotEmpty) {
      final byId = <int, _UserCellDraft>{
        for (final c in master.userCells) c.id: c,
      };
      for (final c in d.userCells) {
        final m = byId[c.id];
        if (m == null) continue;
        c.name ??= m.name;
        c.prompt ??= m.prompt;
        c.value ??= m.value;
      }
    }
    if (d.actions.isEmpty && master.actions.isNotEmpty) {
      for (final a in master.actions) {
        d.actions.add(
          _ActionDraft()
            ..id = a.id
            ..name = a.name
            ..menu = a.menu
            ..prompt = a.prompt,
        );
      }
    }
    if (d.hyperlinks.isEmpty && master.hyperlinks.isNotEmpty) {
      for (final h in master.hyperlinks) {
        d.hyperlinks.add(
          _HyperlinkDraft()
            ..id = h.id
            ..description = h.description
            ..address = h.address
            ..subAddress = h.subAddress
            ..extraInfo = h.extraInfo
            ..frame = h.frame
            ..newWindow = h.newWindow
            ..isDefault = h.isDefault
            ..invisible = h.invisible,
        );
      }
    }
    for (final e in master.formulas.entries) {
      d.formulas.putIfAbsent(e.key, () => e.value);
    }
    d.eventDblClick ??= master.eventDblClick;
    if (!d.locked) d.locked = master.locked;
    if (!d.dontMoveChildren) d.dontMoveChildren = master.dontMoveChildren;
    if (!d.isTextEditTarget) d.isTextEditTarget = master.isTextEditTarget;
    d.selectMode ??= master.selectMode;
    d.displayMode ??= master.displayMode;
    return master;
  }

  /// Merge stencil FieldList into the instance (libvisio `m_stencilFields`).
  void _inheritMasterFields(_ShapeDraft d, _ShapeDraft master) {
    const formatUnknown = 0xffff;
    if (master.fieldRaw.isEmpty && master.fieldDisplays.isEmpty) return;
    if (d.fieldDisplays.isEmpty) {
      d.fieldDisplays.addAll(master.fieldDisplays);
      d.fieldIds.addAll(master.fieldIds);
      d.fieldRaw.addAll(master.fieldRaw);
      d.fieldStringRefs.addAll(
        List<({int nameId, int format, int formatStringId})?>.filled(
          master.fieldDisplays.length,
          null,
        ),
      );
      return;
    }
    // Numeric instance fields inherit the stencil's format below. String
    // references are resolved separately after every Name record is known.
    const cellTypeNumber = 32;
    for (var i = 0; i < d.fieldRaw.length; i++) {
      final raw = d.fieldRaw[i];
      if (raw == null) continue;
      if (raw.format != formatUnknown) continue;
      if (raw.cellType == cellTypeNumber) continue;
      if (i >= master.fieldRaw.length) continue;
      final mRaw = master.fieldRaw[i];
      if (mRaw == null) continue;
      if (mRaw.format == formatUnknown && mRaw.customFormat == null) continue;
      d.fieldRaw[i] = (
        number: raw.number,
        cellType: raw.cellType,
        format: mRaw.format,
        customFormat: raw.customFormat ?? mRaw.customFormat,
      );
    }
  }

  /// Resolve string TextField name ids at shape flush time. Name chunks are
  /// not required to precede TextField chunks in VSD, and libvisio likewise
  /// defers this lookup until its content collector receives the complete
  /// shape. A -2 reference retains the stencil field value.
  void _resolveStringFields(_ShapeDraft d, _ShapeDraft? master) {
    const formatUnknown = 0xffff;
    for (var i = 0; i < d.fieldStringRefs.length; i++) {
      final ref = d.fieldStringRefs[i];
      if (ref == null || i >= d.fieldDisplays.length) continue;
      String display;
      if (master != null &&
          i < master.fieldDisplays.length &&
          ref.nameId == -2) {
        display = master.fieldDisplays[i];
      } else if (ref.nameId >= 0) {
        display = d.localNames[ref.nameId] ?? '';
      } else {
        display = '';
      }
      var format = ref.format;
      if (format == formatUnknown && ref.formatStringId >= 0) {
        format = _parseFormatId(
              d.localNames[ref.formatStringId] ??
                  _names[ref.formatStringId],
            ) ??
            formatUnknown;
      }
      d.fieldDisplays[i] = _applyStringFieldFormat(display, format);
    }
  }

  /// Apply StyleSheet text cells referenced by [textStyleId] (libvisio).
  /// Walks the text-style parent chain so sheets without local CharIX still
  /// inherit fonts from their ancestors.
  void _applyTextStyle(_ShapeDraft d) {
    if (d.textStyleId == _minusOne) return;
    var id = d.textStyleId;
    final seen = <int>{};
    while (id != _minusOne && seen.add(id)) {
      final st = _styles[id];
      if (st == null) break;
      if (st.hasCharStyle) {
        d.fontFamily ??= st.fontFamily;
        if (d.fontEncoding == VsdLegacyTextEncoding.ansi) {
          d.fontEncoding = st.fontEncoding;
        }
        d.fontSizeInches ??= st.fontSizeInches;
        d.textColor ??= st.textColor;
        if (!d.bold) d.bold = st.bold;
        if (!d.italic) d.italic = st.italic;
        if (!d.underline) d.underline = st.underline;
        if (!d.smallCaps) d.smallCaps = st.smallCaps;
        if (d.textCase == VsdxTextCase.normal) d.textCase = st.textCase;
        if (d.textPosition == VsdxTextPosition.normal) {
          d.textPosition = st.textPosition;
        }
        if (!d.strikethrough) d.strikethrough = st.strikethrough;
        if (!d.doubleUnderline) d.doubleUnderline = st.doubleUnderline;
        if (!d.doubleStrikethrough) {
          d.doubleStrikethrough = st.doubleStrikethrough;
        }
        if (d.fontScale == 1.0 && st.fontScale != 1.0) {
          d.fontScale = st.fontScale;
        }
      }
      if (st.hasTextBlock) {
        d.marginLeft ??= st.marginLeft;
        d.marginRight ??= st.marginRight;
        d.marginTop ??= st.marginTop;
        d.marginBottom ??= st.marginBottom;
        d.verticalAlign ??= st.verticalAlign;
        if (d.textBgFilled == null) {
          d.textBgColor ??= st.textBgColor;
          d.textBgFilled = st.textBgFilled;
        } else if (d.textBgFilled == false) {
          d.textBgColor = null;
        }
        d.defaultTabStop ??= st.defaultTabStop;
        d.textDirection ??= st.textDirection;
        if (!d.hideText) d.hideText = st.hideText;
      }
      if (st.hasParaStyle) {
        d.paraAlign ??= st.paraAlign;
        d.indFirst ??= st.indFirst;
        d.indLeft ??= st.indLeft;
        d.indRight ??= st.indRight;
        d.spLine ??= st.spLine;
        d.spBefore ??= st.spBefore;
        d.spAfter ??= st.spAfter;
        d.bullet ??= st.bullet;
        d.bulletStr ??= st.bulletStr;
        d.bulletFont ??= st.bulletFont;
        d.bulletFontSize ??= st.bulletFontSize;
        d.textPosAfterBullet ??= st.textPosAfterBullet;
        d.paraFlags ??= st.paraFlags;
      }
      id = st.textParent;
    }
  }

  VsdxLine? _resolveLineStyle(int styleId) {
    if (styleId == _minusOne) return null;
    var id = styleId;
    final seen = <int>{};
    while (id != _minusOne && seen.add(id)) {
      final style = _styles[id];
      if (style == null) break;
      if (style.line != null) return style.line;
      id = style.lineParent;
    }
    return null;
  }

  (VsdxFill?, VsdxShadow?) _resolveFillStyle(int styleId) {
    if (styleId == _minusOne) return (null, null);
    var id = styleId;
    final seen = <int>{};
    while (id != _minusOne && seen.add(id)) {
      final style = _styles[id];
      if (style == null) break;
      if (style.fill != null || style.shadow != null) {
        return (style.fill, style.shadow);
      }
      id = style.fillParent;
    }
    return (null, null);
  }

  void _readShape(VsdByteReader input) {
    _isShapeStarted = true;
    if (_header.id != _minusOne) _currentShapeId = _header.id;
    _currentShapeLevel = _header.level;
    var parent = 0;
    var masterPage = _minusOne;
    var masterShape = _minusOne;
    var lineStyle = _minusOne;
    var fillStyle = _minusOne;
    var textStyle = _minusOne;
    try {
      if (_version == 5) {
        // Algorithm reference: libvisio VSD5Parser::readShape.
        input.skip(2);
        parent = _getUInt(input);
        input.skip(2);
        masterPage = _getUInt(input);
        masterShape = _getUInt(input);
        lineStyle = _getUInt(input);
        fillStyle = _getUInt(input);
        textStyle = _getUInt(input);
      } else {
        input.skip(10);
        parent = input.readU32();
        input.skip(4);
        masterPage = input.readU32();
        input.skip(4);
        masterShape = input.readU32();
        input.skip(4);
        fillStyle = input.readU32();
        input.skip(4);
        lineStyle = input.readU32();
        input.skip(4);
        textStyle = input.readU32();
      }
    } catch (_) {}

    // Instance cells override; geometry is inherited at flush if still empty.
    final d = _ShapeDraft()
      ..id = _currentShapeId
      ..parent = parent
      ..masterPage = masterPage
      ..masterShape = masterShape
      ..lineStyleId = lineStyle
      ..fillStyleId = fillStyle
      ..textStyleId = textStyle;
    if (!_isStencilStarted && masterPage != _minusOne) {
      final page = _stencils[masterPage];
      if (page != null && page.isNotEmpty) {
        final master = (masterShape != _minusOne ? page[masterShape] : null) ??
            page.values.first;
        d
          ..line = master.line
          ..fill = master.fill
          ..text = master.text
          ..fontSizeInches = master.fontSizeInches
          ..textColor = master.textColor
          ..bold = master.bold
          ..italic = master.italic;
      }
    }
    // Match VSDContentCollector::collectShape ordering: seed from the master,
    // then apply the shape's referenced styles. Any local Line or
    // FillAndShadow record follows this Shape record and remains the final
    // override. Applying styles only as a flush-time `??=` fallback caused a
    // non-null master value to suppress the instance StyleSheet entirely.
    final instanceLineStyle = _resolveLineStyle(lineStyle);
    if (instanceLineStyle != null) d.line = instanceLineStyle;
    if (fillStyle != _minusOne) {
      final instanceFillStyle = _resolveFillStyle(fillStyle);
      if (instanceFillStyle.$1 != null) d.fill = instanceFillStyle.$1;
      if (instanceFillStyle.$2 != null) d.shadow = instanceFillStyle.$2;
    }
    _shape = d;
    _currentShapeId = _minusOne;
  }

  void _readXFormData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    input.skip(1);
    s.pinX = input.readF64();
    input.skip(1);
    s.pinY = input.readF64();
    input.skip(1);
    s.width = input.readF64();
    input.skip(1);
    s.height = input.readF64();
    input.skip(1);
    s.locPinX = input.readF64();
    input.skip(1);
    s.locPinY = input.readF64();
    input.skip(1);
    s.angle = input.readF64();
    s.flipX = input.readU8() != 0;
    s.flipY = input.readU8() != 0;
    s.hasXFormData = true;
  }

  void _readXForm1D(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    s.is1D = true;
    input.skip(1);
    s.beginX = input.readF64();
    input.skip(1);
    s.beginY = input.readF64();
    input.skip(1);
    s.endX = input.readF64();
    input.skip(1);
    s.endY = input.readF64();
  }

  /// Connection Points row (0x99 / 0xba). Layout mirrors other cell rows:
  /// `(tag, f64) × {X,Y}` and optionally `{DirX,DirY}` + Type.
  /// libvisio defines the ids but does not parse them.
  void _readConnectionPoints(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    // 0xba extended rows need DirX/DirY; short/foreign payloads → skip.
    final minLen = _header.chunkType == VsdRecordId.connectionPointsAlt ? 36 : 18;
    if (_header.dataLength < minLen) return;
    try {
      final start = input.offset;
      input.skip(1);
      final x = input.readF64();
      input.skip(1);
      final y = input.readF64();
      var dirX = 0.0;
      var dirY = 0.0;
      var type = 0;
      if (input.offset + 18 <= start + _header.dataLength) {
        input.skip(1);
        dirX = input.readF64();
        input.skip(1);
        dirY = input.readF64();
      }
      if (input.offset < start + _header.dataLength) {
        type = input.readU8();
      }
      // Reject NaN / non-finite (mis-framed chunks).
      if (!x.isFinite || !y.isFinite) return;
      s.connectionPoints.add(
        _ConnectionPointDraft()
          ..id = _header.id
          ..x = x
          ..y = y
          ..dirX = dirX.isFinite ? dirX : 0
          ..dirY = dirY.isFinite ? dirY : 0
          ..type = type,
      );
    } catch (_) {}
  }

  /// Control row (0xaa / 0xa2). Layout (beyond libvisio, which only defines
  /// the ids): `(tag, f64)×{X,Y,XDyn,YDyn}` then `XCon,YCon,CanGlue` bytes.
  /// Longer rows carry formula/string payloads after the fixed prefix.
  void _readControl(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 36) return;
    try {
      final start = input.offset;
      input.skip(1);
      final x = input.readF64();
      input.skip(1);
      final y = input.readF64();
      input.skip(1);
      final dynX = input.readF64();
      input.skip(1);
      final dynY = input.readF64();
      if (!x.isFinite || !y.isFinite) return;
      var conX = 0.0;
      var conY = 0.0;
      var canGlue = false;
      if (input.offset + 3 <= start + _header.dataLength) {
        conX = input.readU8().toDouble();
        conY = input.readU8().toDouble();
        canGlue = input.readU8() != 0;
      }
      // Optional Prompt string in extended payloads (0x60 length-prefixed).
      String? prompt;
      if (_header.dataLength > 47) {
        final end = start + _header.dataLength;
        final remain = end - input.offset;
        if (remain > 0) {
          final tail = input.data.sublist(input.offset, end);
          final strings = _extractVisioAnsiStrings(tail);
          if (strings.isNotEmpty) prompt = strings.first;
        }
      }
      s.controls.add(
        _ControlDraft()
          ..id = _header.id
          ..x = x
          ..y = y
          ..dynX = dynX.isFinite ? dynX : x
          ..dynY = dynY.isFinite ? dynY : y
          ..conX = conX
          ..conY = conY
          ..canGlue = canGlue
          ..prompt = prompt,
      );
    } catch (_) {}
  }

  /// Custom Props / Shape Data row (0xb6). libvisio defines the id but does
  /// not parse it. Best-effort: numeric Value + Type + ANSI Prompt/Label/Format.
  void _readCustomProps(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 9) return;
    try {
      final start = input.offset;
      final end = start + _header.dataLength;
      final tag = input.readU8();
      String? value;
      if (tag >= 0x40 && tag <= 0x42 && input.offset + 8 <= end) {
        final v = input.readF64();
        if (v.isFinite) {
          value = v == v.roundToDouble() ? '${v.toInt()}' : v.toString();
        }
      } else if (input.offset + 8 <= end) {
        input.skip(8); // non-numeric cell placeholder
      }
      var type = 0;
      if (input.offset + 18 <= end) {
        // Four i32 formula markers, then Type (u16).
        input.skip(16);
        type = input.readU16();
      }
      final remain = end - input.offset;
      final strings = remain > 0
          ? _extractVisioAnsiStrings(input.data.sublist(input.offset, end))
          : const <String>[];
      String? prompt;
      String? label;
      String? format;
      if (strings.length >= 3) {
        prompt = strings[0];
        label = strings[1];
        format = strings[2];
      } else if (strings.length == 2) {
        prompt = strings[0];
        label = strings[1];
      } else if (strings.length == 1) {
        label = strings[0];
      }
      final name = s.localNames[_header.id] ?? 'Row${_header.id}';
      // Skip empty placeholder rows (no value/label/prompt).
      if (value == null && label == null && prompt == null) return;
      s.userProperties.add(
        _UserPropDraft()
          ..id = _header.id
          ..name = name
          ..label = label
          ..value = value
          ..prompt = prompt
          ..format = format
          ..type = type,
      );
    } catch (_) {}
  }

  /// Scratch row (0x9e): `(tag, f64)×{X,Y,A,B,C,D}`. libvisio defines the id
  /// but has no reader. Longer rows carry formula payloads after the cells.
  void _readScratch(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 54) return;
    try {
      double cell() {
        input.skip(1);
        return input.readF64();
      }

      final x = cell();
      final y = cell();
      final a = cell();
      final b = cell();
      final c = cell();
      final d = cell();
      if (![x, y, a, b, c, d].every((v) => v.isFinite)) return;
      s.scratchRows.add(
        _ScratchDraft()
          ..id = _header.id
          ..x = x
          ..y = y
          ..a = a
          ..b = b
          ..c = c
          ..d = d,
      );
    } catch (_) {}
  }

  /// User-defined cell (0xb4) → `<Section N="User">`. Best-effort Value +
  /// ANSI name/prompt strings (beyond libvisio).
  void _readUserDefinedCell(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 9) return;
    try {
      final start = input.offset;
      final end = start + _header.dataLength;
      final tag = input.readU8();
      String? value;
      if (tag >= 0x40 && tag <= 0x42 && input.offset + 8 <= end) {
        final v = input.readF64();
        if (v.isFinite) {
          value = v == v.roundToDouble() ? '${v.toInt()}' : v.toString();
        }
      } else if (tag == 0x20 && input.offset + 8 <= end) {
        final v = input.readF64();
        if (v.isFinite && v != 0) {
          value = v == v.roundToDouble() ? '${v.toInt()}' : v.toString();
        }
      } else if (input.offset + 8 <= end) {
        input.skip(8);
      }
      final remain = end - input.offset;
      final strings = remain > 0
          ? _extractVisioAnsiStrings(input.data.sublist(input.offset, end))
          : const <String>[];
      String? name;
      String? prompt;
      if (strings.isNotEmpty) {
        // Prefer identifier-like first string as the User row name.
        name = strings.firstWhere(
          (t) => RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(t),
          orElse: () => strings.first,
        );
        for (final t in strings) {
          if (t != name) {
            prompt = t;
            break;
          }
        }
      }
      name ??= s.localNames[_header.id] ?? 'Row_${_header.id}';
      if (value == null && prompt == null && strings.isEmpty) return;
      s.userCells.add(
        _UserCellDraft()
          ..id = _header.id
          ..name = name
          ..value = value
          ..prompt = prompt,
      );
    } catch (_) {}
  }

  /// Action row (0xa9) → `<Section N="Actions">`. Menu/prompt from ANSI
  /// strings; libvisio defines the id but has no reader.
  void _readActId(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 4) return;
    try {
      final start = input.offset;
      final end = start + _header.dataLength;
      final strings = _extractVisioAnsiStrings(
        input.data.sublist(start, end),
      );
      if (strings.isEmpty) return;
      final menu = strings.first;
      final prompt = strings.length > 1 ? strings[1] : null;
      s.actions.add(
        _ActionDraft()
          ..id = _header.id
          ..name = 'Row_${_header.id}'
          ..menu = menu
          ..prompt = prompt,
      );
    } catch (_) {}
  }

  /// Protection (0xa0). Bool flags as u8 in Visio order; LockMoveX=2 /
  /// LockMoveY=3 drive [VsdxShape.locked] (same canonical bit as vsdx writer).
  void _readProtection(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 4) return;
    try {
      final n = _header.dataLength.clamp(0, input.remaining);
      final bytes = input.data.sublist(input.offset, input.offset + n);
      // Indices: Width=0 Height=1 MoveX=2 MoveY=3 …
      final moveX = bytes.length > 2 && bytes[2] != 0;
      final moveY = bytes.length > 3 && bytes[3] != 0;
      if (moveX || moveY) s.locked = true;
    } catch (_) {}
  }

  /// Group (0xbe). Leading u8 SelectMode / DisplayMode, then flag bytes
  /// including IsTextEditTarget / DontMoveChildren (beyond libvisio).
  void _readGroup(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 2) return;
    try {
      final n = _header.dataLength.clamp(0, input.remaining);
      final bytes = input.data.sublist(input.offset, input.offset + n);
      s.selectMode = bytes[0];
      s.displayMode = bytes[1];
      // Common short layout: SelectMode, DisplayMode, IsDropTarget,
      // IsDropSource, IsSnapTarget, IsTextEditTarget, DontMoveChildren.
      if (bytes.length > 5) s.isTextEditTarget = bytes[5] != 0;
      if (bytes.length > 6) s.dontMoveChildren = bytes[6] != 0;
    } catch (_) {}
  }

  /// Scan Visio ANSI string cells (`0x60` + u8 length + bytes) in a payload.
  List<String> _extractVisioAnsiStrings(List<int> bytes) {
    final out = <String>[];
    for (var i = 0; i + 2 < bytes.length; i++) {
      if (bytes[i] != 0x60) continue;
      final len = bytes[i + 1];
      if (len <= 0 || i + 2 + len > bytes.length) continue;
      final slice = bytes.sublist(i + 2, i + 2 + len);
      // Require mostly printable ASCII (allow trailing NUL).
      var ok = true;
      final chars = <int>[];
      for (final b in slice) {
        if (b == 0) break;
        if (b < 0x20 || b > 0x7e) {
          ok = false;
          break;
        }
        chars.add(b);
      }
      if (!ok || chars.isEmpty) continue;
      out.add(String.fromCharCodes(chars));
      i += 1 + len; // loop +1
    }
    return out;
  }

  /// Hyperlink row (0xc4) → `<Section N="Hyperlink">`.
  ///
  /// Layout from vsdump `chunks_parse_cmds.tbl` (start 196) + POI sample
  /// `visio_with_embeded.vsd`: flags at offset 39 (NewWindow bit0, Default
  /// bit2); string blocks from ~offset 65 as `0x60` + u8 UTF-16LE code-unit
  /// count. libvisio has no reader for this chunk.
  void _readHyperlink(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 8) return;
    try {
      final start = input.offset;
      final end = start + _header.dataLength.clamp(0, input.remaining);
      final bytes = input.data.sublist(start, end);
      var newWindow = false;
      var isDefault = false;
      if (bytes.length > 39) {
        final flags = bytes[39];
        newWindow = (flags & 0x1) != 0;
        isDefault = (flags & 0x4) != 0;
      }
      final strings = _extractVisioUtf16Strings(bytes);
      String? cell(int i) {
        if (i >= strings.length) return null;
        final v = strings[i];
        return v.isEmpty ? null : v;
      }

      s.hyperlinks.add(
        _HyperlinkDraft()
          ..id = _header.id
          ..description = cell(0)
          ..address = cell(1)
          ..subAddress = cell(2)
          ..extraInfo = cell(3)
          ..frame = cell(4)
          ..newWindow = newWindow
          ..isDefault = isDefault,
      );
    } catch (_) {}
  }

  /// Scan Visio UTF-16 string cells (`0x60` + u8 code-unit count + UTF-16LE).
  /// Empty cells (`0x60 0x00` or all-NUL payload) are kept so column order
  /// (Description/Address/SubAddress/ExtraInfo/Frame) stays aligned.
  List<String> _extractVisioUtf16Strings(List<int> bytes) {
    final out = <String>[];
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] != 0x60) continue;
      final cu = bytes[i + 1];
      if (cu < 0 || i + 2 + cu * 2 > bytes.length) continue;
      if (cu == 0) {
        out.add('');
        i += 1;
        continue;
      }
      final units = <int>[];
      var ok = true;
      for (var c = 0; c < cu; c++) {
        final ch = bytes[i + 2 + c * 2] | (bytes[i + 3 + c * 2] << 8);
        if (ch == 0) break;
        if (ch < 0x09 || (ch > 0x0d && ch < 0x20) || ch > 0xfffd) {
          ok = false;
          break;
        }
        units.add(ch);
      }
      if (!ok) continue;
      out.add(String.fromCharCodes(units));
      i += 1 + cu * 2; // loop +1
    }
    return out;
  }

  /// ConnectList (0x72) — page-level glue list header.
  ///
  /// vsdump marks layout Unknown; Apache POI `44594*.vsd` only contain empty
  /// list headers (`childrenListLength=0`). libvisio has no reader. Chunk
  /// alignment is handled by `_handleChunks` seek-to-end; do not invent
  /// Connect From/To rows until a non-empty sample is available.
  /// ConnectList (0x72) — page-level glue list header.
  ///
  /// libvisio only defines `VSD_CONNECT_LIST` and treats 0x72 as a list-chunk
  /// for trailer sizing; there is **no** `readConnectList` / FromSheet–ToSheet
  /// reader. vsdump marks 0x72 Unknown (0x71 is Connection*Points* list).
  /// Public samples (`44594*.vsd`) only have empty list headers
  /// (`childrenListLength=0`). Seek-to-end keeps alignment; do not invent
  /// Connect rows without a non-empty sample to reverse-engineer.
  void _readConnectList(VsdByteReader input) {
    // Intentionally empty — no libvisio layout; seek restores cursor.
  }

  void _readTextXForm(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readTxtXForm.
    final s = _shape;
    if (s == null) return;
    try {
      input.skip(1);
      s.txtPinX = input.readF64();
      input.skip(1);
      s.txtPinY = input.readF64();
      input.skip(1);
      s.txtWidth = input.readF64();
      input.skip(1);
      s.txtHeight = input.readF64();
      input.skip(1);
      s.txtLocPinX = input.readF64();
      input.skip(1);
      s.txtLocPinY = input.readF64();
      input.skip(1);
      s.txtAngle = input.readF64();
    } catch (_) {}
  }

  void _readLine(VsdByteReader input) {
    late final VsdxLine line;
    if (_version == 5) {
      // Algorithm reference: libvisio VSD5Parser::readLine.
      input.skip(1);
      final strokeWidth = input.readF64();
      final colourIndex = input.readU8();
      final colour = _colourFromIndex(colourIndex);
      final pattern = input.readU8();
      input.skip(1);
      final rounding = input.readF64();
      input.skip(1);
      final startMarker = input.readU8();
      final endMarker = input.readU8();
      final lineCap = input.readU8();
      line = VsdxLine(
        color: colour,
        weightInches: strokeWidth,
        pattern: pattern,
        beginArrow: startMarker,
        endArrow: endMarker,
        roundingInches: rounding,
        cap: lineCap == 0
            ? LineCap.round
            : (lineCap == 2 ? LineCap.square : LineCap.extended),
      );
    } else {
      input.skip(1);
      final strokeWidth = input.readF64();
      input.skip(1);
      final r = input.readU8();
      final g = input.readU8();
      final b = input.readU8();
      final a = input.readU8();
      final pattern = input.readU8();
      input.skip(1);
      final rounding = input.readF64();
      input.skip(1);
      final startMarker = input.readU8();
      final endMarker = input.readU8();
      final lineCap = input.readU8();
      final colour = VsdxColor.argb(255 - a, r, g, b);
      line = VsdxLine(
        color: colour,
        weightInches: strokeWidth,
        pattern: pattern,
        beginArrow: startMarker,
        endArrow: endMarker,
        roundingInches: rounding,
        cap: lineCap == 0
            ? LineCap.round
            : (lineCap == 2 ? LineCap.square : LineCap.extended),
      );
    }
    if (_isInStyles) {
      final sid = _currentStyleId != _minusOne ? _currentStyleId : _header.id;
      final st = _styles.putIfAbsent(sid, _StyleDraft.new);
      st.line = line;
    } else {
      _shape?.line = line;
    }
  }

  void _readFillAndShadow(VsdByteReader input) {
    late final VsdxFill fill;
    late final VsdxShadow shadow;
    final inheritedShadowOffsets = vsdResolveLegacyShadowOffsets(
      isStencil: _currentStencilShapes != null,
      stencilX: _stencilShadowOffsetX,
      stencilY: _stencilShadowOffsetY,
      pageX: _currentPage?.shadowOffsetX ?? 0.125,
      pageY: _currentPage?.shadowOffsetY ?? -0.125,
    );
    if (_version == 5) {
      // Algorithm reference: libvisio VSD5Parser::readFillAndShadow.
      final colourFG = _colourFromIndex(input.readU8());
      final colourBG = _colourFromIndex(input.readU8());
      final fillPattern = input.readU8();
      final shadowFG = _colourFromIndex(input.readU8());
      input.skip(1); // shadow BG
      final shadowPattern = input.readU8();
      fill = withLibvisioClassicGradient(VsdxFill(
        foreground: colourFG.withOpacity(1),
        background: colourBG.withOpacity(1),
        pattern: fillPattern,
        foregroundTransparency: 1.0 - (colourFG.alpha / 255.0),
        backgroundTransparency: 1.0 - (colourBG.alpha / 255.0),
      ));
      shadow = VsdxShadow(
        color: shadowFG.withOpacity(1),
        offsetXInches: inheritedShadowOffsets.x,
        offsetYInches: inheritedShadowOffsets.y,
        blurInches: 0,
        transparency: 1.0 - (shadowFG.alpha / 255.0),
        enabled: shadowPattern != 0,
        pattern: shadowPattern == 0 ? 1 : shadowPattern,
      );
    } else {
      final fgIdx = input.readU8();
      var fgR = input.readU8();
      var fgG = input.readU8();
      var fgB = input.readU8();
      var fgA = input.readU8();
      final bgIdx = input.readU8();
      var bgR = input.readU8();
      var bgG = input.readU8();
      var bgB = input.readU8();
      var bgA = input.readU8();
      var colourFG = VsdxColor.argb(255, fgR, fgG, fgB);
      var colourBG = VsdxColor.argb(255, bgR, bgG, bgB);
      var fgTransparency = fgA / 255.0;
      var bgTransparency = bgA / 255.0;
      if (fgR == 0 && fgG == 0 && fgB == 0 && fgA == 0 &&
          bgR == 0 && bgG == 0 && bgB == 0 && bgA == 0) {
        colourFG = _colourFromIndex(fgIdx);
        colourBG = _colourFromIndex(bgIdx);
        fgTransparency = 1.0 - (colourFG.alpha / 255.0);
        bgTransparency = 1.0 - (colourBG.alpha / 255.0);
        colourFG = colourFG.withOpacity(1);
        colourBG = colourBG.withOpacity(1);
      }
      final fillPattern = input.readU8();
      final shadowFGIdx = input.readU8();
      final shadowR = input.readU8();
      final shadowG = input.readU8();
      final shadowB = input.readU8();
      final shadowA = input.readU8();
      final shadowBGIdx = input.readU8();
      final shadowBgR = input.readU8();
      final shadowBgG = input.readU8();
      final shadowBgB = input.readU8();
      final shadowBgA = input.readU8();
      final shadowPattern = input.readU8();
      var shadowColor = VsdxColor.argb(255, shadowR, shadowG, shadowB);
      var shadowTransparency = shadowA / 255.0;
      if (shadowR == 0 &&
          shadowG == 0 &&
          shadowB == 0 &&
          shadowA == 0 &&
          shadowBgR == 0 &&
          shadowBgG == 0 &&
          shadowBgB == 0 &&
          shadowBgA == 0) {
        shadowColor = _colourFromIndex(shadowFGIdx);
        // Read both indices to mirror libvisio's all-zero fallback decision.
        _colourFromIndex(shadowBGIdx);
        shadowTransparency = 1.0 - (shadowColor.alpha / 255.0);
        shadowColor = shadowColor.withOpacity(1);
      }
      var shadowOffsetX = inheritedShadowOffsets.x;
      var shadowOffsetY = inheritedShadowOffsets.y;
      if (_version == 11) {
        try {
          input.skip(2); // shadow type + format
          shadowOffsetX = input.readF64();
          input.skip(1);
          shadowOffsetY = input.readF64();
        } catch (_) {}
      }
      fill = withLibvisioClassicGradient(VsdxFill(
        foreground: colourFG,
        background: colourBG,
        pattern: fillPattern,
        foregroundTransparency: fgTransparency,
        backgroundTransparency: bgTransparency,
      ));
      shadow = VsdxShadow(
        color: shadowColor,
        offsetXInches: shadowOffsetX,
        offsetYInches: shadowOffsetY,
        blurInches: 0,
        transparency: shadowTransparency,
        enabled: shadowPattern != 0,
        pattern: shadowPattern == 0 ? 1 : shadowPattern,
      );
    }
    if (_isInStyles) {
      final sid = _currentStyleId != _minusOne ? _currentStyleId : _header.id;
      final st = _styles.putIfAbsent(sid, _StyleDraft.new);
      st.fill = fill;
      st.shadow = shadow;
    } else {
      _shape?.fill = fill;
      _shape?.shadow = shadow;
    }
  }

  void _readGeomList(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (s.geometries.isNotEmpty &&
        s.currentGeom != null &&
        s.currentGeom!.commands.isEmpty &&
        s.currentGeom!.byId.isEmpty) {
      s.geometries.removeLast();
    }
    final g = _GeomBuilder();
    s.geometries.add(g);
    s.currentGeom = g;
    if (_version == 5) {
      _handleChunkRecords(input, collectStylesOnly: false);
      return;
    }
    if (_header.trailer != 0) {
      try {
        final subHeaderLength = input.readU32();
        var childrenListLength = input.readU32();
        input.skip(subHeaderLength);
        if (childrenListLength > input.remaining) {
          childrenListLength = input.remaining;
        }
        final count = childrenListLength ~/ 4;
        for (var i = 0; i < count; i++) {
          g.order.add(input.readU32());
        }
      } catch (_) {}
    }
  }

  void _readGeometry(VsdByteReader input) {
    final g = _shape?.currentGeom;
    if (g == null) return;
    final flags = input.readU8();
    g.noFill = (flags & 1) != 0;
    g.noLine = (flags & 2) != 0;
    g.noShow = (flags & 4) != 0;
    g.geometryFlagsId = _header.id;
  }

  void _addGeomCmd(int id, VsdxPathCommand cmd) {
    final g = _shape?.currentGeom;
    if (g == null) return;
    g.byId[id] = cmd;
  }

  void _readMoveTo(VsdByteReader input) {
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    _addGeomCmd(_header.id, MoveTo(x, y));
  }

  void _readLineTo(VsdByteReader input) {
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    _addGeomCmd(_header.id, LineTo(x, y));
  }

  void _readArcTo(VsdByteReader input) {
    input.skip(1);
    final x2 = input.readF64();
    input.skip(1);
    final y2 = input.readF64();
    input.skip(1);
    final bow = input.readF64();
    _addGeomCmd(_header.id, ArcTo(x: x2, y: y2, bow: bow));
  }

  void _readEllipse(VsdByteReader input) {
    input.skip(1);
    final cx = input.readF64();
    input.skip(1);
    final cy = input.readF64();
    input.skip(1);
    final xleft = input.readF64();
    input.skip(1);
    final yleft = input.readF64();
    input.skip(1);
    final xtop = input.readF64();
    input.skip(1);
    final ytop = input.readF64();
    _addGeomCmd(
      _header.id,
      EllipseCmd(
        cx: cx,
        cy: cy,
        aX: xleft,
        aY: yleft,
        bX: xtop,
        bY: ytop,
      ),
    );
  }

  void _readEllipticalArcTo(VsdByteReader input) {
    input.skip(1);
    final x3 = input.readF64();
    input.skip(1);
    final y3 = input.readF64();
    input.skip(1);
    final x2 = input.readF64();
    input.skip(1);
    final y2 = input.readF64();
    input.skip(1);
    final angle = input.readF64();
    input.skip(1);
    final ecc = input.readF64();
    _addGeomCmd(
      _header.id,
      EllipticalArcTo(
        x: x3,
        y: y3,
        controlX: x2,
        controlY: y2,
        angle: angle,
        eccentricity: ecc,
      ),
    );
  }

  void _readPageProps(VsdByteReader input) {
    input.skip(1);
    final rawPageWidth = input.readF64();
    input.skip(1);
    final rawPageHeight = input.readF64();
    input.skip(1);
    final shadowOffsetX = input.readF64();
    input.skip(1);
    final shadowOffsetY = input.readF64();
    input.skip(1);
    final pageScale = input.readF64();
    final drawingScaleUnit = input.readU8();
    final props = vsdNormalizePageProps(
      pageWidth: rawPageWidth,
      pageHeight: rawPageHeight,
      pageScale: pageScale,
      drawingScale: input.readF64(),
    );
    if (_isStencilStarted && _currentStencilShapes != null) {
      _stencilShadowOffsetX = shadowOffsetX;
      _stencilShadowOffsetY = shadowOffsetY;
    }
    if (_currentPage != null) {
      _currentPage!.width = props.pageWidth;
      _currentPage!.height = props.pageHeight;
      if (props.scale.isFinite) _currentPage!.scale = props.scale;
      _currentPage!.pageScale = props.pageScale;
      _currentPage!.drawingScale = props.drawingScale;
      _currentPage!.drawingScaleUnit = drawingScaleUnit;
      _currentPage!.shadowOffsetX = shadowOffsetX;
      _currentPage!.shadowOffsetY = shadowOffsetY;
    }
  }

  /// Page record → background-page relationship (libvisio `readPage`).
  void _readPage(VsdByteReader input) {
    final page = _currentPage;
    if (page == null) return;
    try {
      final backgroundId = _version == 5
          ? _getUInt(input)
          : (() {
              input.skip(8); // sub-header length + children-list length
              return input.readU32();
            })();
      page.backgroundPageId =
          backgroundId == _minusOne || backgroundId == page.id
              ? null
              : backgroundId;
    } catch (_) {}
  }

  void _readForeignDataType(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    try {
      input.skip(1);
      final offsetX = input.readF64();
      input.skip(1);
      final offsetY = input.readF64();
      input.skip(1);
      final width = input.readF64();
      input.skip(1);
      final height = input.readF64();
      var foreignType = input.readU16();
      final mapMode = input.readU16();
      if (mapMode == 0x8) foreignType = 0x4;
      input.skip(0x9);
      final foreignFormat = input.readU32();
      s.foreignType = foreignType;
      s.foreignFormat = foreignFormat;
      s.imgOffsetX = offsetX;
      s.imgOffsetY = offsetY;
      s.imgWidth = width;
      s.imgHeight = height;
    } catch (_) {}
  }

  void _readForeignData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength <= 0 || input.remaining < _header.dataLength) return;
    s.foreignBytes = input.readBytes(_header.dataLength);
  }

  /// Append an OLE data chunk (libvisio `VSDParser::readOLEData`).
  void _readOleData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength <= 0 || input.remaining < _header.dataLength) return;
    final chunk = input.readBytes(_header.dataLength);
    final prev = s.foreignBytes;
    if (prev == null || prev.isEmpty) {
      s.foreignBytes = chunk;
      return;
    }
    final out = Uint8List(prev.length + chunk.length);
    out.setRange(0, prev.length, prev);
    out.setRange(prev.length, out.length, chunk);
    s.foreignBytes = out;
  }

  void _readPolylineTo(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readPolylineTo.
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    try {
      input.skip(1);
      final useData = input.readU8();
      if (useData == 0x8b) {
        input.skip(3);
        final dataId = input.readU32();
        final s = _shape;
        if (s == null) return;
        final geometryIndex = s.geometries.length - 1;
        s.currentGeom?.polylineDataIds[_header.id] = dataId;
        final blob = s.polylineData[dataId];
        if (blob != null && blob.points.isNotEmpty) {
          _addGeomCmd(
            _header.id,
            PolylineTo(
              x: x,
              y: y,
              vertices: blob.points,
              vertsRelative: blob.xRel,
              vertsYRelative: blob.yRel,
            ),
          );
        } else {
          s.pendingPolylineData.add((
            geometryIndex: geometryIndex,
            rowId: _header.id,
            x: x,
            y: y,
            dataId: dataId,
          ));
          _addGeomCmd(_header.id, LineTo(x, y)); // placeholder until flush
        }
        return;
      }
      // Formula blocks start at offset 0x30 from chunk data start.
      input.skip(0x9);
      var chunkBytesRead = 0x30;
      var cellRef = 0;
      var length = 0;
      var inputPos = input.offset;
      while (cellRef != 2 &&
          !input.isEnd &&
          _header.dataLength - chunkBytesRead > 4) {
        length = input.readU32();
        if (length == 0) break;
        input.skip(1);
        cellRef = input.readU8();
        if (cellRef < 2) {
          input.skip(length - 6);
        }
        chunkBytesRead += input.offset - inputPos;
        inputPos = input.offset;
      }
      final points = <Offset2D>[];
      var xRel = false;
      var yRel = false;
      if (cellRef == 2) {
        input.skip(1);
        final xType = input.readU16();
        input.skip(1);
        final yType = input.readU16();
        xRel = xType == 0;
        yRel = yType == 0;
        var flag = input.readU8();
        var blockBytesRead = 6 + (input.offset - inputPos);
        inputPos = input.offset;
        while (flag != 0x81 && blockBytesRead < length && !input.isEnd) {
          final x2 = flag == 0x20 ? input.readF64() : input.readU16().toDouble();
          final yFlag = input.readU8();
          final y2 =
              yFlag == 0x20 ? input.readF64() : input.readU16().toDouble();
          points.add(Offset2D(x2, y2));
          flag = input.readU8();
          blockBytesRead += input.offset - inputPos;
          inputPos = input.offset;
        }
      }
      if (points.isEmpty) {
        _addGeomCmd(_header.id, LineTo(x, y));
      } else {
        _addGeomCmd(
          _header.id,
          PolylineTo(
            x: x,
            y: y,
            vertices: points,
            vertsRelative: xRel,
            vertsYRelative: yRel,
          ),
        );
      }
    } catch (_) {
      _addGeomCmd(_header.id, LineTo(x, y));
    }
  }

  void _readNurbsTo(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readNURBSTo (simplified).
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    try {
      final knot = input.readF64();
      final weight = input.readF64();
      final knotPrev = input.readF64();
      final weightPrev = input.readF64();
      input.skip(1);
      final useData = input.readU8();
      if (useData == 0x8a) {
        input.skip(3);
        final dataId = input.readU32();
        final s = _shape;
        if (s == null) return;
        final geometryIndex = s.geometries.length - 1;
        s.currentGeom?.nurbsDataIds[_header.id] = dataId;
        final n = s.nurbsData[dataId];
        if (n != null && n.cps.isNotEmpty) {
          final assembled = vsdAssembleNurbsShapeData(
            dataKnots: n.knots,
            dataWeights: n.weights,
            firstKnot: knotPrev,
            secondLastKnot: knot,
            lastKnot: n.lastKnot,
            firstWeight: weightPrev,
            lastWeight: weight,
          );
          _addGeomCmd(
            _header.id,
            NurbsTo(
              x: x,
              y: y,
              controlPoints: n.cps,
              knots: assembled.knots,
              weights: assembled.weights,
              degree: n.degree,
              cpRelative: n.xRel,
              cpYRelative: n.yRel,
            ),
          );
        } else {
          s.pendingNurbsData.add((
            geometryIndex: geometryIndex,
            rowId: _header.id,
            x: x,
            y: y,
            knot: knot,
            weight: weight,
            knotPrev: knotPrev,
            weightPrev: weightPrev,
            dataId: dataId,
          ));
          _addGeomCmd(_header.id, LineTo(x, y));
        }
        return;
      }
      // Inline formula — best-effort static block; else endpoint only.
      input.skip(9);
      final knotVector = <double>[knotPrev];
      final controlPoints = <Offset2D>[];
      final weights = <double>[weightPrev];
      var degree = 3;
      var xRel = false;
      var yRel = false;
      try {
        // Seek formula cell 6 similarly to libvisio (best-effort).
        var cellRef = 0;
        var length = 0;
        var chunkBytesRead = 0x50;
        var inputPos = input.offset;
        while (cellRef != 6 &&
            !input.isEnd &&
            _header.dataLength - chunkBytesRead > 4) {
          length = input.readU32();
          input.skip(1);
          cellRef = input.readU8();
          if (cellRef < 6) input.skip(length - 6);
          chunkBytesRead += input.offset - inputPos;
          inputPos = input.offset;
        }
        if (cellRef == 6) {
          final paramType = input.readU8();
          late final double lastKnot;
          if (paramType == 0x8a) {
            lastKnot = input.readF64();
            degree = input.readU16();
            final xType = input.readU8();
            final yType = input.readU8();
            xRel = xType == 0;
            yRel = yType == 0;
            var repetitions = input.readU32();
            while (repetitions > 0 && input.remaining >= 32) {
              final cx = input.readF64();
              final cy = input.readF64();
              final k = input.readF64();
              final w = input.readF64();
              controlPoints.add(Offset2D(cx, cy));
              knotVector.add(k);
              weights.add(w);
              repetitions--;
            }
          } else {
            final dynamic = vsdReadDynamicNurbsFormula(
              input,
              firstValueType: paramType,
              blockLength: length,
              payloadStart: inputPos,
            );
            lastKnot = dynamic.lastKnot;
            degree = dynamic.degree;
            xRel = dynamic.xRelative;
            yRel = dynamic.yRelative;
            controlPoints.addAll(dynamic.controlPoints);
            knotVector.addAll(dynamic.knots);
            weights.addAll(dynamic.weights);
          }
          knotVector.add(knot);
          knotVector.add(lastKnot);
          weights.add(weight);
        }
      } catch (_) {}
      if (controlPoints.isEmpty) {
        _addGeomCmd(_header.id, LineTo(x, y));
      } else {
        _addGeomCmd(
          _header.id,
          NurbsTo(
            x: x,
            y: y,
            controlPoints: controlPoints,
            knots: knotVector,
            weights: weights,
            degree: degree,
            cpRelative: xRel,
            cpYRelative: yRel,
          ),
        );
      }
    } catch (_) {
      _addGeomCmd(_header.id, LineTo(x, y));
    }
  }

  void _readInfiniteLine(VsdByteReader input) {
    input.skip(1);
    final x1 = input.readF64();
    input.skip(1);
    final y1 = input.readF64();
    input.skip(1);
    final x2 = input.readF64();
    input.skip(1);
    final y2 = input.readF64();
    _addGeomCmd(
      _header.id,
      InfiniteLineCmd(x: x1, y: y1, a: x2, b: y2),
    );
  }

  void _readSplineStart(VsdByteReader input) {
    // libvisio: x,y, secondKnot, firstKnot, lastKnot, degree
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    final secondKnot = input.readF64();
    final firstKnot = input.readF64();
    final lastKnot = input.readF64();
    final degree = input.readU8();
    _addGeomCmd(
      _header.id,
      SplineStart(
        x: x,
        y: y,
        a: secondKnot,
        b: firstKnot,
        c: lastKnot,
        degree: degree,
      ),
    );
  }

  void _readSplineKnot(VsdByteReader input) {
    input.skip(1);
    final x = input.readF64();
    input.skip(1);
    final y = input.readF64();
    final knot = input.readF64();
    _addGeomCmd(_header.id, SplineKnot(x: x, y: y, knot: knot));
  }

  void _readShapeData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    try {
      final dataType = input.readU8();
      input.skip(15);
      if (dataType == 0x80) {
        final xType = input.readU8();
        final yType = input.readU8();
        var pointCount = input.readU32();
        final maxPts = input.remaining ~/ 16;
        if (pointCount > maxPts) pointCount = maxPts;
        final points = <Offset2D>[];
        for (var i = 0; i < pointCount; i++) {
          points.add(Offset2D(input.readF64(), input.readF64()));
        }
        s.polylineData[_header.id] = (
          points: points,
          xRel: xType == 0,
          yRel: yType == 0,
        );
      } else if (dataType == 0x82) {
        final lastKnot = input.readF64();
        final degree = input.readU16();
        final xType = input.readU8();
        final yType = input.readU8();
        var pointCount = input.readU32();
        final maxPts = input.remaining ~/ 32;
        if (pointCount > maxPts) pointCount = maxPts;
        final cps = <Offset2D>[];
        final knots = <double>[];
        final weights = <double>[];
        for (var i = 0; i < pointCount; i++) {
          cps.add(Offset2D(input.readF64(), input.readF64()));
          knots.add(input.readF64());
          weights.add(input.readF64());
        }
        s.nurbsData[_header.id] = (
          cps: cps,
          knots: knots,
          weights: weights,
          lastKnot: lastKnot,
          degree: degree,
          xRel: xType == 0,
          yRel: yType == 0,
        );
      }
    } catch (_) {}
  }

  void _readTextField(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    // CELL_TYPE_* / format blocks — libvisio VSDParser::readTextField /
    // VSD6Parser::readTextField / VSDFieldList::getString.
    const stringWithoutUnit = 232;
    const cellTypeDate = 40;
    const formatUnknown = 0xffff;
    try {
      if (_version == 5) {
        // VSD5Parser::readTextField — no format block in the chunk; the text
        // stream encodes format as the byte after 0x1E (`formatId + 0x20`).
        input.skip(3);
        final cellType = input.readU8();
        if (cellType == stringWithoutUnit) {
          final nameId = input.readS16();
          s.fieldDisplays.add('');
          s.fieldIds.add(_header.id);
          s.fieldRaw.add(null);
          s.fieldStringRefs.add((
            nameId: nameId,
            format: formatUnknown,
            formatStringId: -1,
          ));
        } else {
          final numeric = input.readF64();
          // Placeholder until `_finalizeVsd5FieldFormats` applies the
          // format byte from the text stream (beyond libvisio VSD5).
          final fmt = cellType == cellTypeDate ? 200 : formatUnknown;
          s.fieldDisplays
              .add(_formatNumericField(numeric, cellType, fmt, null));
          s.fieldIds.add(_header.id);
          s.fieldRaw.add((
            number: numeric,
            cellType: cellType,
            format: fmt,
            customFormat: null,
          ));
          s.fieldStringRefs.add(null);
        }
        return;
      }
      final initial = input.offset;
      input.skip(7);
      final cellType = input.readU8();
      if (cellType == stringWithoutUnit) {
        final nameId = input.readS32();
        input.skip(6);
        final formatStringId = input.readS32();
        // Defer the name and optional format-string lookup until the complete
        // shape-local Name table is available. The inline format block itself
        // is already self-contained.
        final formatNumber = _readFieldFormatBlock(
          input,
          initial: initial,
          blockBase: _version == 6 ? initial + 0x24 : initial + 0x36,
        );
        s.fieldDisplays.add('');
        s.fieldIds.add(_header.id);
        s.fieldRaw.add(null);
        s.fieldStringRefs.add((
          nameId: nameId,
          format: formatNumber,
          formatStringId: formatStringId,
        ));
        final end = initial + _header.dataLength;
        if (end <= input.length && end >= input.offset) input.seek(end);
        return;
      }
      final numeric = input.readF64();
      input.skip(2);
      final formatStringId = input.readS32();

      // Trailing format block (VSD11 @0x36, VSD6 @0x24 from chunk data start).
      var formatNumber = formatUnknown;
      String? customFormat;
      final blockBase = _version == 6 ? initial + 0x24 : initial + 0x36;
      if (blockBase < input.length) {
        input.seek(blockBase);
        var blockIdx = 0;
        final limit = initial + _header.dataLength;
        while (blockIdx != 2 && !input.isEnd && input.offset < limit) {
          final inputPos = input.offset;
          final length = input.readU32();
          if (length == 0) break;
          input.skip(1);
          blockIdx = input.readU8();
          if (blockIdx != 2) {
            final next = inputPos + length;
            if (next > input.length) break;
            input.seek(next);
            continue;
          }
          final typeByte = input.readU8();
          if (typeByte == 0x62) {
            // Numeric format id + 0x80 0xc2 marker (libvisio).
            formatNumber = input.readU16();
            if (input.readU8() != 0x80 || input.readU8() != 0xc2) {
              formatNumber = formatUnknown;
              final next = inputPos + length;
              if (next > input.length) break;
              input.seek(next);
              blockIdx = 0;
              continue;
            }
            break;
          }
          if (typeByte == 0x60) {
            // Custom UTF-16 format string: u8 charCount + UTF-16LE chars
            // (e.g. `<,$>U #,##0.00`). libvisio only handles 0x62+0x80/0xc2.
            final charCount = input.readU8();
            if (charCount > 0 && input.remaining >= charCount * 2) {
              customFormat =
                  _decodeUtf16Le(input.readBytes(charCount * 2));
            }
            break;
          }
          if (typeByte == 0x70) {
            // Alternate numeric/date format payload seen in Gantt samples
            // (tdf76829): u32 + u32(formatId) + trailer. libvisio ignores this.
            if (input.remaining >= 8) {
              input.readU32();
              final fmt = input.readU32();
              if (fmt <= 221) formatNumber = fmt;
            }
            break;
          }
          // Unknown type — skip block.
          final next = inputPos + length;
          if (next > input.length) break;
          input.seek(next);
          blockIdx = 0;
        }
      }
      if (formatNumber == formatUnknown && customFormat == null) {
        if (cellType == cellTypeDate) {
          formatNumber = 200; // VSD_FIELD_FORMAT_MsoDateShort
        } else if (formatStringId >= 0) {
          final parsed = _parseFormatId(
              s.localNames[formatStringId] ?? _names[formatStringId]);
          if (parsed != null) formatNumber = parsed;
        }
      }
      // Multidimensional (233): primary F64 is often a denormal placeholder
      // (libvisio TODO). A trailing typed result `0x46 <sqIn F64> <unit> 0x02`
      // carries the real area in square inches plus display unit.
      var effectiveCell = cellType;
      var effectiveNumeric = numeric;
      if (cellType == 233) {
        final saved = input.offset;
        input.seek(initial);
        final payload = input.readBytes(
          (_header.dataLength).clamp(0, input.length - initial),
        );
        input.seek(saved);
        final resolved = _resolveMultidimensional(payload);
        if (resolved != null) {
          effectiveNumeric =
              _sqInchesToArea(resolved.sqInches, resolved.unit);
          effectiveCell = _areaDisplayCellType(resolved.unit);
        }
      }
      s.fieldDisplays.add(_formatNumericField(
          effectiveNumeric, effectiveCell, formatNumber, customFormat));
      s.fieldIds.add(_header.id);
      s.fieldRaw.add((
        number: effectiveNumeric,
        cellType: effectiveCell,
        format: formatNumber,
        customFormat: customFormat,
      ));
      s.fieldStringRefs.add(null);
      final end = initial + _header.dataLength;
      if (end <= input.length && end >= input.offset) input.seek(end);
    } catch (_) {}
  }

  /// Parse Multidimensional TextField trailer: `0x46` + sq-inches F64 + unit + `0x02`.
  /// Returns square-inches value and VisUnitCodes display unit, or null.
  ({double sqInches, int unit})? _resolveMultidimensional(Uint8List payload) {
    // Scan from the end for the last well-formed typed double result.
    for (var i = payload.length - 11; i >= 0; i--) {
      if (payload[i] != 0x46) continue;
      if (payload[i + 10] != 0x02) continue;
      final unit = payload[i + 9];
      // Accept known linear/area VisUnitCodes used as area display units.
      const areaUnits = {
        36, // Acre
        37, // Hectare
        65, // Inches → in^2
        66, // Feet → ft^2
        68, // Miles → mi^2
        69, // Centimeters → cm^2
        70, // Millimeters → mm^2
        71, // Meters → m^2
        72, // Kilometers → km^2
        75, // Yards → yd^2
      };
      if (!areaUnits.contains(unit)) continue;
      final bd = ByteData.sublistView(payload, i + 1, i + 9);
      final sqIn = bd.getFloat64(0, Endian.little);
      if (!sqIn.isFinite) continue;
      return (sqInches: sqIn, unit: unit);
    }
    return null;
  }

  /// Convert square inches → display area for Multidimensional unit codes.
  double _sqInchesToArea(double sqIn, int unit) {
    return switch (unit) {
      36 => sqIn / 6272640.0, // acres
      37 => sqIn / 15500031.000062, // hectares
      65 => sqIn, // sq in
      66 => sqIn / 144.0, // sq ft
      68 => sqIn / 4014489600.0, // sq mi
      69 => sqIn * 6.4516, // cm^2
      70 => sqIn * 645.16, // mm^2
      71 => sqIn * 0.00064516, // m^2
      72 => sqIn * 6.4516e-10, // km^2
      75 => sqIn / 1296.0, // sq yd
      _ => sqIn,
    };
  }

  /// Map VisUnitCodes used as area display → synthetic cell types for suffixes.
  int _areaDisplayCellType(int unit) {
    return switch (unit) {
      36 => 36, // acres
      37 => 37, // ha
      65 => 239, // in^2
      66 => 240, // ft^2
      68 => 245, // mi^2
      69 => 238, // cm^2
      70 => 243, // mm^2
      71 => 242, // m^2
      72 => 244, // km^2
      75 => 241, // yd^2
      _ => unit,
    };
  }

  /// Parse `{<N>}` / `esc(N)` format-string ids (libvisio `parseFormatId`).
  int? _parseFormatId(String? s) {
    if (s == null || s.isEmpty) return null;
    final m = RegExp(r'^\s*(?:\{<(\d+)>\}|esc\((\d+)\))\s*$').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? m.group(2)!);
  }

  /// Read a TextField trailing format block; returns format id or `0xffff`.
  int _readFieldFormatBlock(
    VsdByteReader input, {
    required int initial,
    required int blockBase,
  }) {
    const formatUnknown = 0xffff;
    if (blockBase >= input.length) return formatUnknown;
    try {
      input.seek(blockBase);
      var blockIdx = 0;
      final limit = initial + _header.dataLength;
      while (blockIdx != 2 && !input.isEnd && input.offset < limit) {
        final inputPos = input.offset;
        final length = input.readU32();
        if (length == 0) break;
        input.skip(1);
        blockIdx = input.readU8();
        if (blockIdx != 2) {
          final next = inputPos + length;
          if (next > input.length) break;
          input.seek(next);
          continue;
        }
        final typeByte = input.readU8();
        if (typeByte == 0x62) {
          final formatNumber = input.readU16();
          if (input.readU8() != 0x80 || input.readU8() != 0xc2) {
            final next = inputPos + length;
            if (next > input.length) break;
            input.seek(next);
            blockIdx = 0;
            continue;
          }
          return formatNumber;
        }
        // Non-numeric blocks ignored for string fields.
        break;
      }
    } catch (_) {}
    return formatUnknown;
  }

  /// Apply StrNormal / StrLower / StrUpper (formats 37–39).
  String _applyStringFieldFormat(String text, int format) {
    switch (format) {
      case 38: // StrLower
        return text.toLowerCase();
      case 39: // StrUpper
        return text.toUpperCase();
      case 37: // StrNormal
      default:
        return text;
    }
  }

  /// Format a numeric/date field (subset of libvisio `VSDNumericField::getString`).
  String _formatNumericField(
    double value,
    int cellType,
    int format, [
    String? customFormat,
    int? defaultDrawingUnit,
  ]) {
    const formatUnknown = 0xffff;
    const cellTypePageUnits = 63;
    const cellTypeDrawingUnits = 64;

    // Resolve DrawingUnits / PageUnits → page default first (libvisio
    // `getString`), so Unknown-format fallbacks still use the right unit.
    var effectiveType = cellType;
    var effectiveFormat = format;
    final pageUnit = defaultDrawingUnit ??
        _currentPage?.drawingScaleUnit ??
        0;
    if ((cellType == cellTypeDrawingUnits || cellType == cellTypePageUnits) &&
        pageUnit != 0) {
      effectiveType = pageUnit;
    }

    // Custom Visio format string from type-0x60 block (e.g. `<,$>U #,##0.00`).
    if (customFormat != null && customFormat.isNotEmpty) {
      final custom = _applyCustomFormat(value, customFormat);
      if (custom != null) return custom;
    }

    if (format == formatUnknown) {
      // Gantt / property cells often store calendar values as CELL_TYPE_Number
      // (32) with no format block (libvisio returns empty). Treat Visio serial
      // days in a sane year range as dates.
      if (cellType == 32 && _looksLikeVisioDateSerial(value)) {
        final frac = (value - value.truncateToDouble()).abs();
        final fmt = frac > 1e-4 ? 211 : 200; // datetime vs MsoDateShort
        final formatted = _formatVisioDate(value, fmt);
        if (formatted != null) return formatted;
      }
      // Length/angle units with Unknown format: still convert (values are
      // always inches/radians internally). Prefer 1 decimal + unit — common
      // for dimension labels when the format block is Missing and stencil
      // inheritance has not supplied one yet.
      final converted = _convertNumber(effectiveType, value);
      final suffix = _unitSuffix(effectiveType);
      if (suffix.isNotEmpty) {
        return '${converted.toStringAsFixed(1)}$suffix';
      }
      return _formatFieldNumber(value);
    }

    // Date / time formats (Visio serial day → UTC).
    if (_isDateFormat(format) || cellType == 40) {
      final formatted = _formatVisioDate(value, format);
      if (formatted != null) return formatted;
    }

    // Resolve AngleUnits → concrete angle cell type (libvisio getString).
    if (cellType == 80) {
      // CELL_TYPE_AngleUnits
      if (format == 11) {
        effectiveType = 83; // Radians
      } else if (format == 12) {
        effectiveType = 81; // Degrees
      } else {
        effectiveType = 82; // DegreeMinuteSecond
      }
    }
    if (effectiveType == 82 && format == 1) {
      effectiveFormat = 12; // NumGenDefUnits on DMS → Degrees
    }

    final converted = _convertNumber(effectiveType, value);
    final suffix = _unitSuffix(effectiveType);

    // Common numeric precision formats.
    switch (effectiveFormat) {
      case 0: // NumGenNoUnits
        return _formatFieldNumber(converted);
      case 1: // NumGenDefUnits
        return '${_formatFieldNumber(converted)}$suffix';
      case 2: // 0PlNoUnits
        return converted.round().toString();
      case 3: // 0PlDefUnits
        return '${converted.round()}$suffix';
      case 4: // 1PlNoUnits
        return converted.toStringAsFixed(1);
      case 5:
        return '${converted.toStringAsFixed(1)}$suffix';
      case 6: // 2PlNoUnits
        return converted.toStringAsFixed(2);
      case 7:
        return '${converted.toStringAsFixed(2)}$suffix';
      case 8: // 3PlNoUnits
        return converted.toStringAsFixed(3);
      case 9:
        return '${converted.toStringAsFixed(3)}$suffix';
      case 11: // Radians
        return '${_convertNumber(83, value).toStringAsFixed(4)} rad';
      case 12: // Degrees (or DMS when cell is DegreeMinuteSecond)
        if (effectiveType == 82) {
          final deg = value * 57.2957795;
          final degInt = deg.truncateToDouble();
          final minTotal = (deg - degInt).abs() * 60.0;
          final minInt = minTotal.truncateToDouble();
          final sec = (minTotal - minInt) * 60.0;
          return '${degInt.round()} deg ${minInt.round()} min ${sec.round()} sec';
        }
        return '${_convertNumber(81, value).round()} deg';
      case 10: // FeetAndInches   (<,FEET/INCH>0.000 u)
      case 13: // FeetAndInches1Pl (<,FEET/INCH># #/# u)
      case 14: // FeetAndInches2Pl (<,FEET/INCH># #/## u)
        // libvisio still TODOs these; emit Visio-style marks (e.g. 20'-6").
        return _formatFeetAndInches(value, effectiveFormat);
      case 15: // Fraction1PlNoUnits  (0 #/#)
      case 16: // Fraction1PlDefUnits (0 #/# u)
      case 17: // Fraction2PlNoUnits  (0 #/##)
      case 18: // Fraction2PlDefUnits (0 #/## u)
        final denom =
            (effectiveFormat == 15 || effectiveFormat == 16) ? 8 : 16;
        final frac = _formatFraction(converted, denom);
        final withUnit = effectiveFormat == 16 || effectiveFormat == 18;
        return withUnit ? '$frac$suffix' : frac;
      default:
        return _formatFieldNumber(converted);
    }
  }

  /// Feet-and-inches display for Visio field formats 10/13/14. libvisio's
  /// `VSDFieldList` leaves these as TODO; Visio renders `20'-6"` style marks.
  /// [valueInches] is the raw internal length (Visio stores lengths in inches).
  String _formatFeetAndInches(double valueInches, int format) {
    final neg = valueInches < 0;
    final total = valueInches.abs();
    final feet = (total / 12).floor();
    final inches = total - feet * 12;
    final sign = neg ? '-' : '';
    if (format == 10) {
      // Decimal inches; strip trailing zeros so whole inches read `6"`.
      var inchStr = inches.toStringAsFixed(3);
      if (inchStr.contains('.')) {
        inchStr = inchStr
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
      }
      return "$sign$feet'-$inchStr\"";
    }
    // 13 → single-digit fraction (…/8); 14 → double-digit fraction (…/16).
    final denom = format == 13 ? 8 : 16;
    final whole = inches.floor();
    final num = ((inches - whole) * denom).round();
    if (num >= denom) {
      final bumped = whole + 1;
      if (bumped >= 12) return "$sign${feet + 1}'-0\"";
      return "$sign$feet'-$bumped\"";
    }
    if (num == 0) return "$sign$feet'-$whole\"";
    final g = _gcdInt(num, denom);
    return "$sign$feet'-$whole ${num ~/ g}/${denom ~/ g}\"";
  }

  /// Whole + reduced fraction display for Visio formats 15–18 (`0 #/#`).
  String _formatFraction(double value, int denom) {
    final neg = value < 0;
    final v = value.abs();
    final whole = v.floor();
    final num = ((v - whole) * denom).round();
    final sign = neg ? '-' : '';
    if (num >= denom) return '$sign${whole + 1}';
    if (num == 0) return '$sign$whole';
    final g = _gcdInt(num, denom);
    return '$sign$whole ${num ~/ g}/${denom ~/ g}';
  }

  int _gcdInt(int a, int b) {
    a = a.abs();
    b = b.abs();
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a == 0 ? 1 : a;
  }

  /// Inches/radians/days → display units (libvisio `convertNumber`).
  double _convertNumber(int cellType, double number) {
    switch (cellType) {
      case 33: // Percent
        return number * 100.0;
      case 44: // ElapsedDay
        return number;
      case 43: // ElapsedWeek
        return number / 7.0;
      case 45: // ElapsedHour
        return number * 24.0;
      case 46: // ElapsedMin
        return number * 24.0 * 60.0;
      case 47: // ElapsedSec
        return number * 24.0 * 60.0 * 60.0;
      case 65: // Inches
        return number;
      case 50: // Points
        return number * 72.0;
      case 51: // Picas
        return number * 6.0;
      case 53: // Didots
        return number * 67.75;
      case 54: // Ciceros
        return number * 5.644444444444;
      case 66: // Feet
        return number * 0.0833333333;
      case 69: // Centimeters
        return number * 2.54;
      case 68: // Miles
        return number / 63360.0;
      case 70: // Millimeters
        return number * 25.4;
      case 71: // Meters
        return number * 0.0254;
      case 72: // Kilometers
        return number * 0.0000254;
      case 75: // Yards
        return number * 0.0277777778;
      case 76: // NauticalMiles
        return number / 72913.386;
      case 83: // Radians
        return number;
      case 81: // Degrees
      case 82: // DegreeMinuteSecond
        return number * 57.2957795;
      default:
        return number;
    }
  }

  /// Best-effort Visio custom format (`<,$>U #,##0.00`, `0.00%`, …).
  String? _applyCustomFormat(double value, String format) {
    var f = format.trim();
    // Locale/currency bracket `<,$>` / `<,€>` — extract symbol before strip.
    String? currency;
    final bracket = RegExp(r'^<([^>]*)>').firstMatch(f);
    if (bracket != null) {
      final inner = bracket.group(1)!;
      if (inner.contains(r'$')) {
        currency = r'$';
      } else if (inner.contains('€')) {
        currency = '€';
      } else {
        final sym = RegExp(r'[^,\s0-9.]').firstMatch(inner);
        if (sym != null) currency = sym.group(0);
      }
      f = f.substring(bracket.end).trim();
    }
    // `U` is the currency placeholder (prefix or suffix position).
    final uPos = f.indexOf('U');
    final currencyPrefix = currency != null &&
        uPos >= 0 &&
        (!f.contains('#') || uPos < f.indexOf('#'));
    f = f.replaceAll('U', '').trim();
    if (f.isEmpty && currency == null) return null;

    if (currency == null) {
      if (f.contains(r'$')) {
        currency = r'$';
        f = f.replaceAll(r'$', '');
      } else if (f.contains('€')) {
        currency = '€';
        f = f.replaceAll('€', '');
      }
    }
    f = f.trim();

    final isPercent = f.contains('%');
    if (isPercent) {
      f = f.replaceAll('%', '');
      value = value * 100.0;
    }

    final dot = f.lastIndexOf('.');
    var decimals = 0;
    if (dot >= 0) {
      decimals = f.substring(dot + 1).replaceAll(RegExp(r'[^0#]'), '').length;
    }
    final useGrouping = f.contains(',');
    var body = value.toStringAsFixed(decimals);
    if (useGrouping) {
      final parts = body.split('.');
      final neg = parts[0].startsWith('-');
      var intPart = neg ? parts[0].substring(1) : parts[0];
      final buf = StringBuffer();
      for (var i = 0; i < intPart.length; i++) {
        final fromEnd = intPart.length - i;
        if (i > 0 && fromEnd % 3 == 0) buf.write(',');
        buf.write(intPart[i]);
      }
      body = '${neg ? '-' : ''}${buf.toString()}'
          '${parts.length > 1 ? '.${parts[1]}' : ''}';
    }
    if (isPercent) body = '$body%';
    if (currency != null) {
      body = currencyPrefix ? '$currency$body' : '$body $currency';
    }
    return body;
  }

  bool _isDateFormat(int format) {
    if (format >= 20 && format <= 36) return true;
    if (format >= 44 && format <= 81) return true;
    if (format >= 200 && format <= 221) return true;
    return false;
  }

  String? _formatVisioDate(double serial, int format) {
    // libvisio: time_t = 86400 * serial - 2209161600.0
    final unixSec = 86400.0 * serial - 2209161600.0;
    if (!unixSec.isFinite) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (unixSec * 1000.0).round(),
      isUtc: true,
    );
    String two(int n) => n.toString().padLeft(2, '0');
    String y2() => two(dt.year % 100);
    final formattedTime = vsdFormatVisioTimeField(dt, format);
    if (formattedTime != null) return formattedTime;
    switch (format) {
      case 20: // DateShort weekday abbr
        return _weekdayAbbr(dt.weekday);
      case 21:
        return _weekdayName(dt.weekday);
      case 22:
      case 23:
      case 203: // MsoDateShortAlt — libvisio `%m/%d/%y`
        return '${two(dt.month)}/${two(dt.day)}/$y2()';
      case 24: // MMM d, yyyy
        return '${_monthAbbr(dt.month)} ${dt.day}, ${dt.year}';
      case 25:
      case 202: // MMMM d, yyyy
        return '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
      case 26: // d/M/yy
        return '${dt.day}/${dt.month}/$y2()';
      case 27: // dd/MM/yy
        return '${two(dt.day)}/${two(dt.month)}/$y2()';
      case 28:
        return '${dt.day} ${_monthAbbr(dt.month)}, ${dt.year}';
      case 29:
      case 208: // d MMMM yyyy
        return '${dt.day} ${_monthName(dt.month)} ${dt.year}';
      case 201: // dddd, MMMM dd, yyyy
        return '${_weekdayName(dt.weekday)}, ${_monthName(dt.month)} '
            '${two(dt.day)}, ${dt.year}';
      case 204: // yyyy-MM-dd
        return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
      case 205: // d-MMM-yy
        return '${dt.day}-${_monthAbbr(dt.month)}-$y2()';
      case 206: // M.d.yyyy — libvisio `%m.%d.%Y`
        return '${two(dt.month)}.${two(dt.day)}.${dt.year}';
      case 207:
        return '${_monthAbbr(dt.month)}.${dt.day}, $y2()';
      case 209:
        return '${_monthName(dt.month)} $y2()';
      case 210:
        return '${_monthAbbr(dt.month)}-$y2()';
      case 200: // MsoDateShort — libvisio `%m/%d/%Y` (zero-padded)
      default:
        // Most remaining date codes map to MM/dd/yyyy (libvisio).
        return '${two(dt.month)}/${two(dt.day)}/${dt.year}';
    }
  }

  /// Visio serial day roughly covering 1954–2064 (Gantt bars, prop dates).
  bool _looksLikeVisioDateSerial(double value) {
    if (!value.isFinite) return false;
    return value >= 20000 && value <= 60000;
  }

  String _unitSuffix(int cellType) {
    // Match libvisio `getUnitString`, plus Multidimensional area suffixes.
    return switch (cellType) {
      33 => '%',
      36 => ' acres',
      37 => ' ha',
      43 => ' ew.',
      44 => ' ed.',
      45 => ' eh.',
      46 => ' em.',
      47 => ' es.',
      50 => ' pt',
      51 => ' p',
      53 => ' d',
      54 => ' c',
      65 => ' in',
      66 => ' ft',
      68 => ' mi',
      69 => ' cm',
      70 => ' mm',
      71 => ' m',
      72 => ' km',
      75 => ' yd',
      76 => ' nm.',
      81 => ' deg',
      83 => ' rad',
      84 => ' min',
      85 => ' sec',
      // Synthetic Multidimensional area units (not in libvisio).
      238 => ' cm^2',
      239 => ' in^2',
      240 => ' ft^2',
      241 => ' yd^2',
      242 => ' m^2',
      243 => ' mm^2',
      244 => ' km^2',
      245 => ' mi^2',
      _ => '',
    };
  }

  /// Visio ShapeSheet `U=` token for a CELL_TYPE length unit.
  String? _visioUnitToken(int cellType) {
    return switch (cellType) {
      50 => 'PT',
      51 => 'PICA',
      65 => 'IN',
      66 => 'FT',
      68 => 'MI',
      69 => 'CM',
      70 => 'MM',
      71 => 'M',
      72 => 'KM',
      75 => 'YD',
      _ => null,
    };
  }

  String _monthAbbr(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];

  String _monthName(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];

  String _weekdayAbbr(int w) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];

  String _weekdayName(int w) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ][w - 1];

  String _formatFieldNumber(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e12) {
      return v.round().toString();
    }
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s;
  }


  /// Event (0x84) → EventDblClick / EventXFMod / EventDrop formulas.
  ///
  /// vsdump: TheText@20, BlockStarts@36 (older layout). VSD11 samples store
  /// formula blocks from offset 17 as `u32 length + u8 + u8 cellRef + body`
  /// (same block header as libvisio NURBS formula walk). Cell refs:
  /// 1=TheText, 2=EventDblClick, 3=EventXFMod, 4=EventDrop.
  /// Recognises OPENTEXTWIN (`80 4c`) and RUNADDONW from UTF-16 `0x60` strings.
  void _readEvent(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 8) return;
    try {
      final start = input.offset;
      final end = start + _header.dataLength.clamp(0, input.remaining);
      final bytes = input.data.sublist(start, end);
      // Prefer VSD11 block stream at 17; fall back to vsdump BlockStarts@36.
      var pos = bytes.length > 17 ? 17 : 0;
      if (bytes.length > 36) {
        final lenAt17 = bytes.length >= 21
            ? bytes[17] |
                (bytes[18] << 8) |
                (bytes[19] << 16) |
                (bytes[20] << 24)
            : 0;
        final plausible17 = lenAt17 >= 6 &&
            lenAt17 < 0x10000 &&
            17 + lenAt17 <= bytes.length;
        if (!plausible17) pos = 36;
      }
      while (pos + 6 <= bytes.length) {
        final length = bytes[pos] |
            (bytes[pos + 1] << 8) |
            (bytes[pos + 2] << 16) |
            (bytes[pos + 3] << 24);
        if (length < 6 || pos + length > bytes.length) break;
        final cellRef = bytes[pos + 5];
        final body = bytes.sublist(pos + 6, pos + length);
        final name = switch (cellRef) {
          1 => 'TheText',
          2 => 'EventDblClick',
          3 => 'EventXFMod',
          4 => 'EventDrop',
          _ => null,
        };
        if (name != null) {
          final formula = _decompileEventFormula(body);
          if (formula != null && formula.isNotEmpty) {
            s.formulas[name] = formula;
            if (name == 'EventDblClick') {
              s.eventDblClick ??= '0';
            }
          }
        }
        pos += length;
      }
    } catch (_) {}
  }

  /// Best-effort Event formula decompile from a discretionary block body.
  String? _decompileEventFormula(List<int> body) {
    if (body.isEmpty) return null;
    final strings = _extractVisioUtf16Strings(body);
    // RUNADDONW("Addon","/CMD=…") — common Visio add-on EventDblClick.
    if (strings.length >= 2) {
      final a = strings[0];
      final b = strings[1];
      if (a.isNotEmpty &&
          (b.startsWith('/') || b.toUpperCase().startsWith('CMD'))) {
        return 'RUNADDONW(${_visioQuote(a)},${_visioQuote(b)})';
      }
      if (a.isNotEmpty && b.isNotEmpty) {
        return 'RUNADDONW(${_visioQuote(a)},${_visioQuote(b)})';
      }
    }
    if (strings.length == 1 && strings[0].isNotEmpty) {
      return 'RUNADDON(${_visioQuote(strings[0])})';
    }
    // OPENTEXTWIN() — function token `80 4c … 40` seen across VSD11 samples
    // and matching workflow.vsdx EventDblClick.
    for (var i = 0; i + 1 < body.length; i++) {
      if (body[i] == 0x80 && body[i + 1] == 0x4c) {
        return 'OPENTEXTWIN()';
      }
    }
    return null;
  }

  String _visioQuote(String s) => '"${s.replaceAll('"', '""')}"';

  void _readMisc(VsdByteReader input) {
    // Algorithm reference: libvisio VSD5/VSD6/VSDParser::readMisc.
    final s = _shape;
    if (s == null) return;
    try {
      final initial = input.offset;
      final flags = input.readU8();
      s.hideText = (flags & 0x20) != 0;
      s.hasMisc = true;
      // VSD5 has no connector-target extension blocks.
      if (_version == 5) return;

      final limit = (initial + _header.dataLength + _header.trailer)
          .clamp(0, input.length);
      final firstBlock = initial + (_version == 6 ? 23 : 45);
      if (firstBlock + 4 > limit) return;
      input.seek(firstBlock);

      while (input.offset + 4 <= limit) {
        final blockStart = input.offset;
        final length = input.readU32();
        if (length == 0) break;
        final blockEnd = blockStart + length;
        if (length < 6 || blockEnd > limit) break;

        final blockType = input.readU8();
        input.skip(1);
        if (blockType == 2 && input.offset + 14 <= blockEnd) {
          final marker1 = input.readU8();
          final marker2 = input.readU32();
          final shapeId = input.readU32();
          final marker3 = input.readU8();
          final marker4 = input.readU32();
          if (marker1 == 0x74 &&
              marker2 == 0x6000004e &&
              marker3 == 0x7a &&
              marker4 == 0x40000073) {
            if (s.beginTargetId == null) {
              s.beginTargetId = shapeId;
            } else {
              s.endTargetId ??= shapeId;
            }
          }
        }
        input.seek(blockEnd);
      }
    } catch (_) {}
  }

  void _readLayer(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readLayer.
    final page = _currentPage;
    if (page == null || _isStencilStarted) return;
    try {
      input.skip(8);
      final colourId = input.readU8();
      VsdxColor? color;
      var colorTrans = 0.0;
      if (colourId == 0xff) {
        input.skip(4);
      } else {
        final r = input.readU8();
        final g = input.readU8();
        final b = input.readU8();
        final a = input.readU8();
        color = VsdxColor.argb(255, r, g, b);
        colorTrans = a / 255.0;
      }
      input.skip(1);
      final visible = input.readU8() != 0;
      final printable = input.readU8() != 0;
      final named = page.elementNames[_header.id];
      page.layers.add(
        VsdxLayer(
          id: _header.id,
          name: (named != null && _isPlausibleDisplayName(named))
              ? named
              : 'Layer ${_header.id}',
          visible: visible,
          print: printable,
          color: color,
          colorTrans: colorTrans,
        ),
      );
    } catch (_) {}
  }

  void _readLayerMem(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readLayerMem /
    // VSD6Parser::readLayerMem (ANSI byte count, not UTF-16).
    final s = _shape;
    if (s == null) return;
    try {
      input.skip(13);
      final textLength = input.readU8();
      if (textLength == 0) return;
      final String text;
      if (_version < 11) {
        if (input.remaining < textLength) return;
        text = _decodeAnsi(input.readBytes(textLength));
      } else {
        final n = textLength * 2;
        if (input.remaining < n) return;
        text = _decodeUtf16Le(input.readBytes(n));
      }
      final ids = <int>[];
      for (final part in text.split(';')) {
        final v = int.tryParse(part.trim());
        // VSDContentCollector parses the complete value as `int % ';'`.
        if (v == null) {
          s.layerMemberIds = const <int>[];
          return;
        }
        ids.add(v);
      }
      s.layerMemberIds = ids;
    } catch (_) {}
  }

  void _readName2(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readName2 (VSD11 UTF-16) /
    // VSD6Parser::readName2 (VSD5/6 ANSI).
    try {
      if (_version < 11) {
        // getInt: s32 (VSD6) / s16 (VSD5)
        if (_version == 5) {
          input.readS16();
        } else {
          input.readS32();
        }
        final chars = <int>[];
        while (!input.isEnd) {
          final c = input.readU8();
          if (c == 0) break;
          chars.add(c);
        }
        final text = decodeVsdLegacyText(
          chars,
          VsdLegacyTextEncoding.ansi,
        );
        if (text.isNotEmpty) _names[_header.id] = text;
      } else {
        input.skip(4);
        final units = <int>[];
        while (!input.isEnd) {
          final cu = input.readU16();
          units.add(cu & 0xff);
          units.add((cu >> 8) & 0xff);
          if (cu == 0) break;
        }
        final text = _decodeUtf16Le(Uint8List.fromList(units));
        if (text.isNotEmpty) _names[_header.id] = text;
      }
    } catch (_) {}
  }

  void _readName(VsdByteReader input) {
    // Shape-local Name table (libvisio `VSDParser::readName` →
    // `m_shape.m_names[id]`). Holds format ids (`esc(N)`) and string-field
    // payloads — NOT the shape's display name (that comes from NameIDX).
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength <= 0 || input.remaining < _header.dataLength) return;
    try {
      final raw = input.readBytes(_header.dataLength);
      final text = _version < 11 ? _decodeAnsi(raw) : _decodeUtf16Le(raw);
      if (text.isNotEmpty) s.localNames[_header.id] = text;
    } catch (_) {}
  }

  void _readNameIdx(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readNameIDX /
    // VSD5Parser::readNameIDX (U16 records).
    try {
      final names = <int, String>{};
      if (_version == 5) {
        var recordCount = input.readU16();
        final max = input.remaining ~/ 4;
        if (recordCount > max) recordCount = max;
        for (var i = 0; i < recordCount; i++) {
          final nameId = input.readU16();
          final elementId = input.readU16();
          final n = _names[nameId];
          if (n != null) names[elementId] = n;
        }
      } else {
        var recordCount = input.readU32();
        final max = input.remaining ~/ 13;
        if (recordCount > max) recordCount = max;
        for (var i = 0; i < recordCount; i++) {
          final nameId = input.readU32();
          input.readU32(); // duplicate nameId
          final elementId = input.readU32();
          input.skip(1);
          final n = _names[nameId];
          if (n != null) names[elementId] = n;
        }
      }
      _namesByLevel[_header.level] = names;
      _absorbPageElementNames(names);
    } catch (_) {}
  }

  void _readNameIdx123(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readNameIDX123.
    try {
      final end = input.offset + _header.dataLength;
      final names = <int, String>{};
      while (!input.isEnd && input.offset < end) {
        final nameId = _getUInt(input);
        final elementId = _getUInt(input);
        final n = _names[nameId];
        if (n != null) names[elementId] = n;
      }
      _namesByLevel[_header.level] = names;
      _absorbPageElementNames(names);
    } catch (_) {}
  }

  /// Bind page NameIDX rows to shapes / layers (beyond libvisio, which keeps
  /// names only for its IR). Style / stencil / prop-field tables are skipped.
  void _absorbPageElementNames(Map<int, String> names) {
    if (_isInStyles || _isStencilStarted) return;
    final page = _currentPage;
    if (page == null || names.isEmpty) return;
    if (!_mapLooksLikeDisplayNames(names)) return;
    for (final e in names.entries) {
      if (!_isPlausibleDisplayName(e.value)) continue;
      page.elementNames.putIfAbsent(e.key, () => e.value);
    }
    for (final s in page.shapes) {
      final n = page.elementNames[s.id];
      if (n != null) s.shapeName ??= n;
    }
    for (var i = 0; i < page.layers.length; i++) {
      final layer = page.layers[i];
      final n = page.elementNames[layer.id];
      if (n != null && layer.name.startsWith('Layer ')) {
        page.layers[i] = layer.copyWith(name: n);
      }
    }
  }

  bool _mapLooksLikeDisplayNames(Map<int, String> names) {
    for (final v in names.values) {
      if (v.contains(' ') || v.contains('"') || v.contains('-')) return true;
      if (_knownStencilDisplayNames.contains(v)) return true;
    }
    return false;
  }

  bool _isPlausibleDisplayName(String raw) {
    final n = raw.trim();
    if (n.isEmpty || RegExp(r'^\d+$').hasMatch(n)) return false;
    if (n.contains('esc(') || n.contains('{<')) return false;
    if (n.startsWith('vis') || n.startsWith('Vis')) return false;
    if (n.length <= 2 && !n.contains('"')) return false;
    // ShapeSheet-ish tokens: LX1, Closed2, WallFill, RefLn…
    if (RegExp(r'^[A-Za-z]+[0-9]+$').hasMatch(n)) return false;
    if (RegExp(r'^[A-Z][a-z]+[A-Z]').hasMatch(n)) return false;
    if (n.contains(' ') || n.contains('"') || n.contains('-')) return true;
    if (_knownStencilDisplayNames.contains(n)) return true;
    // Single Title-Case word (Wall, Building, Space, Guide…).
    return RegExp(r'^[A-Z][a-z]+$').hasMatch(n);
  }

  static const _knownStencilDisplayNames = {
    'Wall',
    'Door',
    'Window',
    'Space',
    'Building',
    'Guide',
    'Dimension',
    'Furniture',
  };

  String? _nameFromId(int id, int level) {
    final map = _namesByLevel[level];
    if (map == null) return null;
    return map[id];
  }

  void _readFontFace(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readFont.
    try {
      input.skip(4);
      final units = <int>[];
      for (var i = 0; i < 32 && !input.isEnd; i++) {
        final lo = input.readU8();
        final hi = input.readU8();
        if (lo == 0 && hi == 0) break;
        units.add(lo);
        units.add(hi);
      }
      final name = _decodeUtf16Le(Uint8List.fromList(units));
      if (name.isNotEmpty) {
        _fonts[_header.id] =
            _VsdFontInfo(name, VsdLegacyTextEncoding.ansi);
      }
    } catch (_) {}
  }

  void _readFontIx(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readFontIX.
    // Layout: skip(2) + getUInt(codePage) + ANSI name bytes (nul-terminated).
    try {
      final start = input.offset;
      input.skip(2);
      var codePage = _getUInt(input) & 0xff;
      final remaining = _header.dataLength - (input.offset - start);
      if (remaining <= 0) return;
      final chars = <int>[];
      for (var i = 0; i < remaining && !input.isEnd; i++) {
        final c = input.readU8();
        if (c == 0) break;
        chars.add(c);
      }
      if (chars.isEmpty) return;
      var nameBytes = chars;
      var nameProbe = String.fromCharCodes(chars);
      // When codePage==0, libvisio derives it from name suffixes and strips them.
      if (codePage == 0) {
        const suffixCodePages = <String, int>{
          ' CE': 0xee,
          ' Cyrillic': 0xcc,
          ' Cyr': 0xcc,
          ' CYR': 0xcc,
          ' Baltic': 0xba,
          ' Greek': 0xa1,
          ' Tur': 0xa2,
          ' TUR': 0xa2,
          ' Hebrew': 0xb1,
          ' Arabic': 0xb2,
          ' Thai': 0xde,
        };
        for (final entry in suffixCodePages.entries) {
          if (nameProbe.endsWith(entry.key)) {
            codePage = entry.value;
            nameBytes = chars.sublist(0, chars.length - entry.key.length);
            nameProbe = nameProbe.substring(
              0,
              nameProbe.length - entry.key.length,
            );
            break;
          }
        }
        if (nameProbe.startsWith('GOST')) codePage = 0xcc;
      }
      final encoding = vsdLegacyEncodingForCodePage(codePage);
      final name = decodeVsdLegacyText(nameBytes, encoding);
      if (name.isNotEmpty) {
        _fonts[_header.id] = _VsdFontInfo(
          name,
          encoding,
        );
      }
    } catch (_) {}
  }

  void _readTextBlock(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readTextBlock.
    final shape = (!_isInStyles) ? _shape : null;
    final style = (_isInStyles && _currentStyleId != _minusOne)
        ? _styles.putIfAbsent(_currentStyleId, _StyleDraft.new)
        : null;
    if (shape == null && style == null) return;
    try {
      input.skip(1);
      final marginLeft = input.readF64();
      input.skip(1);
      final marginRight = input.readF64();
      input.skip(1);
      final marginTop = input.readF64();
      input.skip(1);
      final marginBottom = input.readF64();
      final valign = input.readU8();
      final verticalAlign = switch (valign) {
        0 => VsdxVertAlign.top,
        2 => VsdxVertAlign.bottom,
        _ => VsdxVertAlign.middle,
      };
      final bgIdx = input.readU8();
      late final bool isBgFilled;
      late final VsdxColor? textBgColor;
      late final double defaultTabStop;
      late final int textDirection;
      if (_version == 5) {
        // VSD5 TextBlock ends after the palette colour index.
        isBgFilled = bgIdx != 0;
        textBgColor = isBgFilled ? _colourFromIndex(bgIdx - 1) : null;
        defaultTabStop = 0;
        textDirection = 0;
      } else {
        // VSD6/11 carry cached RGBA plus the newer tab/direction cells.
        input.skip(4);
        isBgFilled = bgIdx != 0 && bgIdx != 0xff;
        textBgColor = isBgFilled ? _colourFromIndex(bgIdx - 1) : null;
        input.skip(1);
        defaultTabStop = input.readF64();
        input.skip(12);
        textDirection = input.readU8();
      }
      void apply(dynamic t) {
        t.marginLeft = marginLeft;
        t.marginRight = marginRight;
        t.marginTop = marginTop;
        t.marginBottom = marginBottom;
        t.verticalAlign = verticalAlign;
        t.textBgFilled = isBgFilled;
        t.textBgColor = textBgColor;
        t.defaultTabStop = defaultTabStop;
        t.textDirection = textDirection;
        if (t is _StyleDraft) t.hasTextBlock = true;
      }
      if (shape != null) apply(shape);
      if (style != null) apply(style);
    } catch (_) {}
  }

  void _readText(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    if (_header.dataLength < 8) return;
    input.skip(8);
    final n = _header.dataLength - 8;
    if (n <= 0 || input.remaining < n) return;
    final raw = input.readBytes(n);
    if (_version == 11) {
      s.text = _decodeUtf16Le(raw);
    } else {
      s.legacyTextBytes = raw;
      // Temporary fallback until CharIX order/code pages are available.
      s.text = decodeVsdLegacyText(raw, VsdLegacyTextEncoding.ansi);
    }
  }

  void _readCharIx(VsdByteReader input) {
    final shape = (!_isInStyles) ? _shape : null;
    final style = (_isInStyles && _currentStyleId != _minusOne)
        ? _styles.putIfAbsent(_currentStyleId, _StyleDraft.new)
        : null;
    if (shape == null && style == null) return;
    try {
      late final int charCount;
      late final int fontID;
      VsdxColor? textColor;
      var bold = false;
      var italic = false;
      var underline = false;
      var smallCaps = false;
      var allCaps = false;
      var initCaps = false;
      var superscript = false;
      var subscript = false;
      var doubleUnderline = false;
      var strikethrough = false;
      var doubleStrikethrough = false;
      var fontScale = 1.0;
      double? fontSizeInches;
      if (_version == 5) {
        // Algorithm reference: libvisio VSD5Parser::readCharIX.
        charCount = input.readU16();
        fontID = input.readU16();
        textColor = _colourFromIndex(input.readU8());
        var fontMod = input.readU8();
        bold = (fontMod & 1) != 0;
        italic = (fontMod & 2) != 0;
        underline = (fontMod & 4) != 0;
        smallCaps = (fontMod & 8) != 0;
        fontMod = input.readU8();
        allCaps = (fontMod & 1) != 0;
        initCaps = (fontMod & 2) != 0;
        fontMod = input.readU8();
        superscript = (fontMod & 1) != 0;
        subscript = (fontMod & 2) != 0;
        fontScale = input.readU16() / 10000.0;
        input.skip(2);
        fontSizeInches = input.readF64();
        // VSD5: trailing strike flags are present in the stream but unused
        // by libvisio (`#if 0`); skip when available.
      } else {
        // Algorithm reference: libvisio VSDParser::readCharIX.
        charCount = input.readU32();
        fontID = input.readU16();
        input.skip(1);
        final r = input.readU8();
        final g = input.readU8();
        final b = input.readU8();
        final a = input.readU8();
        textColor = VsdxColor.argb(255 - a, r, g, b);
        var fontMod = input.readU8();
        bold = (fontMod & 1) != 0;
        italic = (fontMod & 2) != 0;
        underline = (fontMod & 4) != 0;
        smallCaps = (fontMod & 8) != 0;
        fontMod = input.readU8();
        allCaps = (fontMod & 1) != 0;
        initCaps = (fontMod & 2) != 0;
        fontMod = input.readU8();
        superscript = (fontMod & 1) != 0;
        subscript = (fontMod & 2) != 0;
        fontScale = input.readU16() / 10000.0;
        input.skip(2);
        fontSizeInches = input.readF64();
        fontMod = input.readU8();
        doubleUnderline = (fontMod & 1) != 0;
        strikethrough = (fontMod & 4) != 0;
        doubleStrikethrough = (fontMod & 0x20) != 0;
      }
      final textCase = allCaps
          ? VsdxTextCase.allCaps
          : (initCaps ? VsdxTextCase.initialCaps : VsdxTextCase.normal);
      final textPosition = superscript
          ? VsdxTextPosition.superscript
          : (subscript
              ? VsdxTextPosition.subscript
              : VsdxTextPosition.normal);
      final font = _fonts[fontID];
      final family = font?.name;
      final encoding = font?.encoding ?? VsdLegacyTextEncoding.ansi;
      void apply(dynamic t) {
        if (family != null) t.fontFamily ??= family;
        if (t.fontEncoding == VsdLegacyTextEncoding.ansi) {
          t.fontEncoding = encoding;
        }
        if (textColor != null) t.textColor = textColor;
        t.bold = bold;
        t.italic = italic;
        t.underline = underline;
        t.smallCaps = smallCaps;
        t.textCase = textCase;
        t.textPosition = textPosition;
        t.strikethrough = strikethrough;
        t.doubleUnderline = doubleUnderline;
        t.doubleStrikethrough = doubleStrikethrough;
        t.fontScale = fontScale;
        t.fontSizeInches = fontSizeInches;
        if (t is _StyleDraft) t.hasCharStyle = true;
      }
      if (shape != null) {
        apply(shape);
        shape.charRuns.add(_CharRunDraft()
          ..id = _header.id
          ..charCount = charCount
          ..fontFamily = family
          ..encoding = encoding
          ..fontSizeInches = fontSizeInches
          ..textColor = textColor
          ..bold = bold
          ..italic = italic
          ..underline = underline
          ..smallCaps = smallCaps
          ..textCase = textCase
          ..textPosition = textPosition
          ..strikethrough = strikethrough
          ..doubleUnderline = doubleUnderline
          ..doubleStrikethrough = doubleStrikethrough
          ..fontScale = fontScale);
      }
      if (style != null) apply(style);
    } catch (_) {}
  }

  void _readParaIx(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readParaIX / VSD5Parser::readParaIX.
    final shape = (!_isInStyles) ? _shape : null;
    final style = (_isInStyles && _currentStyleId != _minusOne)
        ? _styles.putIfAbsent(_currentStyleId, _StyleDraft.new)
        : null;
    if (shape == null && style == null) return;
    try {
      final start = input.offset;
      final charCount =
          _version == 5 ? input.readU16() : input.readU32();
      input.skip(1);
      final indFirst = input.readF64();
      input.skip(1);
      final indLeft = input.readF64();
      input.skip(1);
      final indRight = input.readF64();
      input.skip(1);
      final spLine = input.readF64();
      input.skip(1);
      final spBefore = input.readF64();
      input.skip(1);
      final spAfter = input.readF64();
      final align = input.readU8();
      final paraAlign = switch (align) {
        1 => VsdxHorzAlign.center,
        2 => VsdxHorzAlign.right,
        3 => VsdxHorzAlign.justify,
        _ => VsdxHorzAlign.left,
      };
      int? bullet;
      String? bulletFont;
      double? bulletFontSize;
      double? textPosAfterBullet;
      int? paraFlags;
      String? bulletStr;
      if (_version == 5) {
        // VSD5 has no bullet payload, but libvisio still materialises the
        // format's concrete defaults so a master/style bullet is cleared.
        bullet = 0;
        bulletStr = '';
        bulletFont = '';
        bulletFontSize = 0;
        textPosAfterBullet = 0;
        paraFlags = 0;
      } else {
        bullet = input.readU8();
        input.skip(4);
        bulletStr = '';
        bulletFont = '';
        if (_version == 6) {
          // Visio 2000 ParaIX ends its fixed fields with flags + 5 reserved
          // bytes. It has no BulletFont/BulletFontSize/TextPosAfterBullet
          // fields; those zero values are nevertheless concrete in libvisio.
          paraFlags = input.readU32();
          input.skip(5);
          bulletFontSize = 0;
          textPosAfterBullet = 0;
        } else {
          final fontID = input.readU16();
          if (fontID != 0) bulletFont = _fonts[fontID]?.name ?? '';
          input.skip(2);
          bulletFontSize = input.readF64();
          input.skip(1);
          textPosAfterBullet = input.readF64();
          paraFlags = input.readU32();
          input.skip(34);
        }
        var remaining = _header.dataLength - (input.offset - start);
        while (remaining >= 4 && !input.isEnd) {
          final blockLength = input.readU32();
          if (blockLength == 0 || blockLength > remaining) break;
          final blockEnd = input.offset + blockLength - 4;
          final blockType = input.readU8();
          final blockIdx = input.readU8();
          if (blockType == 2 && blockIdx == 8 && input.remaining >= 2) {
            input.skip(1);
            final numBytes = (_version == 6 ? 1 : 2) * input.readU8();
            if (numBytes > 0 && input.remaining >= numBytes) {
              final bytes = input.readBytes(numBytes);
              bulletStr =
                  _version == 6 ? _decodeAnsi(bytes) : _decodeUtf16Le(bytes);
            }
          }
          if (blockEnd > input.length) break;
          input.seek(blockEnd);
          remaining -= blockLength;
        }
      }
      void apply(dynamic t) {
        t.indFirst = indFirst;
        t.indLeft = indLeft;
        t.indRight = indRight;
        t.spLine = spLine;
        t.spBefore = spBefore;
        t.spAfter = spAfter;
        t.paraAlign = paraAlign;
        if (bullet != null) t.bullet = bullet;
        if (bulletFont != null) t.bulletFont = bulletFont;
        if (bulletFontSize != null) t.bulletFontSize = bulletFontSize;
        if (textPosAfterBullet != null) {
          t.textPosAfterBullet = textPosAfterBullet;
        }
        if (paraFlags != null) t.paraFlags = paraFlags;
        if (bulletStr != null) t.bulletStr = bulletStr;
        if (t is _StyleDraft) t.hasParaStyle = true;
      }
      if (shape != null) {
        apply(shape);
        shape.paraRuns.add(_ParaRunDraft()
          ..id = _header.id
          ..charCount = charCount
          ..paraAlign = paraAlign
          ..indFirst = indFirst
          ..indLeft = indLeft
          ..indRight = indRight
          ..spLine = spLine
          ..spBefore = spBefore
          ..spAfter = spAfter
          ..bullet = bullet
          ..bulletStr = bulletStr
          ..bulletFont = bulletFont
          ..bulletFontSize = bulletFontSize
          ..textPosAfterBullet = textPosAfterBullet
          ..paraFlags = paraFlags);
      }
      if (style != null) apply(style);
    } catch (_) {}
  }

  /// TabsData (libvisio `VSDParser::readTabsData`) — 0x88 / 0x96 / 0x97 / 0xb5.
  void _readTabsData(VsdByteReader input) {
    final s = _shape;
    if (s == null) return;
    try {
      final numChars = _getUInt(input);
      final numStops = input.readU8();
      final draft = _TabSetDraft()
        ..id = _header.id
        ..numChars = numChars;
      for (var i = 0; i < numStops; i++) {
        input.skip(1);
        final position = input.readF64();
        final alignment = input.readU8();
        input.readU8(); // leader (not modelled)
        draft.stops.add(VsdxTabStop(
          positionInches: position,
          alignment: alignment,
        ));
      }
      s.tabRuns.add(draft);
    } catch (_) {}
  }

  void _readColours(VsdByteReader input) {
    input.skip(2);
    final numColours = input.readU8();
    input.skip(1);
    _colours.clear();
    for (var i = 0; i < numColours; i++) {
      final r = input.readU8();
      final g = input.readU8();
      final b = input.readU8();
      final a = input.readU8();
      _colours.add(VsdxColor.argb(255 - a, r, g, b));
    }
  }

  void _readStyleSheet(VsdByteReader input) {
    // Algorithm reference: libvisio VSDParser::readStyleSheet /
    // VSD5Parser::readStyleSheet (parent line/fill/text style ids).
    _currentStyleId = _header.id;
    final st = _styles.putIfAbsent(_header.id, _StyleDraft.new);
    try {
      if (_version == 5) {
        input.skip(10);
        st.lineParent = _getUInt(input);
        st.fillParent = _getUInt(input);
        st.textParent = _getUInt(input);
      } else {
        input.skip(0x22);
        st.lineParent = input.readU32();
        input.skip(4);
        st.fillParent = input.readU32();
        input.skip(4);
        st.textParent = input.readU32();
      }
    } catch (_) {}
  }

  void _readShapeList(VsdByteReader input) {
    if (_version == 5) {
      _handleChunkRecords(input, collectStylesOnly: false);
      return;
    }
    if (!_isShapeStarted && _currentPage != null) {
      _readListOrder(input, into: _currentPage!.shapeOrder);
    } else if (_isShapeStarted && _shape != null) {
      _readListOrder(input, into: _shape!.childOrder);
    } else {
      _readListOrder(input, into: null);
    }
  }

  /// Decode VSD5/VSD6 text one CharIX span at a time. CharIX/ParaIX/TabsData
  /// counts are byte counts in these formats, so remap them to decoded UTF-16
  /// code-unit counts before the rich-text walker consumes them.
  String _decodeLegacyShapeText(_ShapeDraft d) {
    final stored = d.legacyTextBytes;
    if (stored == null || stored.isEmpty) return d.text ?? '';

    var byteLength = stored.length;
    while (byteLength > 0 && stored[byteLength - 1] == 0) {
      byteLength--;
    }
    final bytes = stored.sublist(0, byteLength);
    if (bytes.isEmpty) return '';

    final spans = <_LegacyTextSpan>[];
    var byteOffset = 0;
    if (d.charRuns.isEmpty) {
      spans.add(_LegacyTextSpan(0, bytes.length, d.fontEncoding));
    } else {
      for (final run in d.charRuns) {
        if (byteOffset >= bytes.length) {
          run.charCount = 0;
          continue;
        }
        final rawCount = run.charCount == 0
            ? bytes.length - byteOffset
            : run.charCount.clamp(0, bytes.length - byteOffset);
        final end = byteOffset + rawCount;
        spans.add(_LegacyTextSpan(byteOffset, end, run.encoding));
        run.charCount = decodeVsdLegacyText(
          bytes.sublist(byteOffset, end),
          run.encoding,
        ).length;
        byteOffset = end;
      }
      if (byteOffset < bytes.length) {
        spans.add(_LegacyTextSpan(
          byteOffset,
          bytes.length,
          d.charRuns.last.encoding,
        ));
      }
    }

    int decodedLength(int start, int end) {
      var length = 0;
      for (final span in spans) {
        final partStart = start > span.start ? start : span.start;
        final partEnd = end < span.end ? end : span.end;
        if (partStart >= partEnd) continue;
        length += decodeVsdLegacyText(
          bytes.sublist(partStart, partEnd),
          span.encoding,
        ).length;
      }
      return length;
    }

    void remapCounts<T>(
      List<T> rows,
      int Function(T row) read,
      void Function(T row, int value) write,
    ) {
      var start = 0;
      for (final row in rows) {
        final rawCount = read(row);
        if (start >= bytes.length) {
          write(row, 0);
          continue;
        }
        final end = rawCount == 0
            ? bytes.length
            : start + rawCount.clamp(0, bytes.length - start);
        write(row, decodedLength(start, end));
        start = end;
      }
    }

    remapCounts<_ParaRunDraft>(
      d.paraRuns,
      (row) => row.charCount,
      (row, value) => row.charCount = value,
    );
    remapCounts<_TabSetDraft>(
      d.tabRuns,
      (row) => row.numChars,
      (row, value) => row.numChars = value,
    );

    final out = StringBuffer();
    for (final span in spans) {
      out.write(decodeVsdLegacyText(
        bytes.sublist(span.start, span.end),
        span.encoding,
      ));
    }
    return out.toString();
  }

  /// Read a list chunk trailer of child ids (libvisio `readCharList` /
  /// `readParaList` / `readFieldList` / `readShapeList`).
  void _readListOrder(VsdByteReader input, {List<int>? into}) {
    if (_header.trailer == 0) return;
    try {
      final subHeaderLength = input.readU32();
      var childrenListLength = input.readU32();
      input.skip(subHeaderLength);
      if (childrenListLength > input.remaining) {
        childrenListLength = input.remaining;
      }
      final count = childrenListLength ~/ 4;
      if (into == null) {
        input.skip(count * 4);
        return;
      }
      for (var i = 0; i < count; i++) {
        into.add(input.readU32());
      }
    } catch (_) {}
  }

  void _readShapeId(VsdByteReader input) {
    try {
      final shapeId = _getUInt(input);
      if (_isShapeStarted) {
        _shape?.childShapeIds[_header.id] = shapeId;
      } else {
        _currentPage?.shapeIds[_header.id] = shapeId;
      }
    } catch (_) {}
  }

  VsdxColor _colourFromIndex(int idx) {
    if (idx < 0 || idx >= _colours.length) return VsdxColor.black;
    return _colours[idx];
  }

  String _decodeAnsi(Uint8List raw) {
    if (raw.isEmpty) return '';
    final nul = raw.indexOf(0);
    final bytes = nul < 0 ? raw : raw.sublist(0, nul);
    return decodeVsdLegacyText(bytes, VsdLegacyTextEncoding.ansi);
  }

  String _decodeUtf16Le(Uint8List raw) {
    if (raw.isEmpty) return '';
    final units = <int>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final cu = raw[i] | (raw[i + 1] << 8);
      if (cu == 0) break;
      if (cu == 0x0d || cu == 0x0e) {
        units.add(0x0a);
      } else {
        units.add(cu);
      }
    }
    return String.fromCharCodes(units);
  }

  VsdxDocument _buildDocument() {
    if (_pages.isEmpty) {
      return VsdxDocument(
        pages: [
          VsdxPage(
            id: 0,
            name: 'Page-1',
            widthInches: 8.5,
            heightInches: 11.0,
            shapes: const [],
          ),
        ],
        applicationName: 'Editor for Visio Diagrams',
      );
    }
    final images = <String, VsdxImage>{};
    var imageSeq = 0;
    final pages = <VsdxPage>[];
    final firstPageId = _pages.first.id;
    for (var i = 0; i < _pages.length; i++) {
      final p = _pages[i];
      // PageScale=0 is valid in libvisio and collapses the page and drawable
      // coordinates to zero. Only a non-finite parsed ratio needs a fallback.
      final scale = p.scale.isFinite ? p.scale : 1.0;
      // Apply drawing scale (libvisio: page size and coords *= m_scale).
      for (final s in p.shapes) {
        _applyScale(s, scale);
        _registerForeignImage(s, images, () => ++imageSeq);
      }
      pages.add(
        VsdxPage(
          id: i == 0 ? 0 : p.id,
          name: p.name,
          widthInches: p.width * scale,
          heightInches: p.height * scale,
          shapes: _assembleShapes(
            p.shapes,
            shapeOrder: vsdResolveShapeOrder(p.shapeIds, p.shapeOrder),
            defaultDrawingUnit: p.drawingScaleUnit,
          ),
          layers: List<VsdxLayer>.from(p.layers),
          connects: List<VsdxConnect>.from(p.connects),
          isBackgroundPage: p.isBackgroundPage,
          backgroundPageId: p.backgroundPageId == firstPageId
              ? 0
              : p.backgroundPageId,
          pageSheet: VsdxPageSheet(
            // libvisio materialises the drawing ratio into the page and
            // drawable coordinates, but emits shadow offsets verbatim.
            // Neutralise the ratio in the editable model so VSD -> VSDX
            // synthesis cannot apply it a second time on reopen.
            shadowOffsetXInches: p.shadowOffsetX,
            shadowOffsetYInches: p.shadowOffsetY,
            pageScale: 1,
            pageScaleUnit: 'IN',
            drawingScale: 1,
            drawingScaleUnit: _visioUnitToken(p.drawingScaleUnit) ?? 'IN',
            // Binary libvisio only announces PageSheet boundaries; it does
            // not expose PageLayout/LineJump cells to the drawing collector.
            // LibreOffice therefore renders ordinary crossing strokes. Mark
            // jumps off explicitly so the editor's unset=enabled UI default
            // cannot invent arcs while importing classic VSD pages.
            lineJumpCode: 0,
          ),
        ),
      );
    }
    return VsdxDocument(
      pages: pages,
      images: images.isEmpty ? ImageRegistry.empty : ImageRegistry(images),
      applicationName: 'Editor for Visio Diagrams',
    );
  }

  void _applyScale(_ShapeDraft d, double s) {
    if (s == 1.0) return;
    d.pinX *= s;
    d.pinY *= s;
    d.width *= s;
    d.height *= s;
    d.locPinX *= s;
    d.locPinY *= s;
    if (d.beginX != null) d.beginX = d.beginX! * s;
    if (d.beginY != null) d.beginY = d.beginY! * s;
    if (d.endX != null) d.endX = d.endX! * s;
    if (d.endY != null) d.endY = d.endY! * s;
    for (final c in d.connectionPoints) {
      c.x *= s;
      c.y *= s;
    }
    for (final c in d.controls) {
      c.x *= s;
      c.y *= s;
      c.dynX *= s;
      c.dynY *= s;
    }
    for (final r in d.scratchRows) {
      // X/Y are typically length cells; leave A–D (angles / flags) alone.
      r.x *= s;
      r.y *= s;
    }
    // Font sizes and paragraph/text-block metrics stay in physical units;
    // libvisio applies the drawing scale to the text frame, not typography.
    if (d.txtPinX != null) d.txtPinX = d.txtPinX! * s;
    if (d.txtPinY != null) d.txtPinY = d.txtPinY! * s;
    if (d.txtWidth != null) d.txtWidth = d.txtWidth! * s;
    if (d.txtHeight != null) d.txtHeight = d.txtHeight! * s;
    if (d.txtLocPinX != null) d.txtLocPinX = d.txtLocPinX! * s;
    if (d.txtLocPinY != null) d.txtLocPinY = d.txtLocPinY! * s;
    if (d.imgOffsetX != null) d.imgOffsetX = d.imgOffsetX! * s;
    if (d.imgOffsetY != null) d.imgOffsetY = d.imgOffsetY! * s;
    if (d.imgWidth != null) d.imgWidth = d.imgWidth! * s;
    if (d.imgHeight != null) d.imgHeight = d.imgHeight! * s;
    // libvisio applies the page drawing scale when materialising line
    // properties as well as geometry. Materialise the default too: otherwise
    // style-less shapes receive an unscaled default later in [_toShape].
    final line = d.line ?? VsdxLine.defaultLine;
    d.line = line.copyWith(
      weightInches: line.weightInches * s,
      roundingInches: line.roundingInches * s,
    );
    // Shadow offsets are physical source-cell values. VSDContentCollector
    // leaves them unscaled even when page geometry and line widths use
    // PageScale / DrawingScale.
    for (final g in d.geometries) {
      final scaled = <int, VsdxPathCommand>{};
      for (final e in g.byId.entries) {
        scaled[e.key] = _scaleCommand(e.value, s);
      }
      g.byId
        ..clear()
        ..addAll(scaled);
    }
  }

  VsdxPathCommand _scaleCommand(VsdxPathCommand c, double s) {
    return switch (c) {
      MoveTo(:final x, :final y) => MoveTo(x * s, y * s),
      LineTo(:final x, :final y) => LineTo(x * s, y * s),
      ArcTo(:final x, :final y, :final bow) =>
        ArcTo(x: x * s, y: y * s, bow: bow * s),
      EllipticalArcTo(
        :final x,
        :final y,
        :final controlX,
        :final controlY,
        :final angle,
        :final eccentricity
      ) =>
        EllipticalArcTo(
          x: x * s,
          y: y * s,
          controlX: controlX * s,
          controlY: controlY * s,
          angle: angle,
          eccentricity: eccentricity,
        ),
      EllipseCmd(:final cx, :final cy, :final aX, :final aY, :final bX, :final bY) =>
        EllipseCmd(
          cx: cx * s,
          cy: cy * s,
          aX: aX * s,
          aY: aY * s,
          bX: bX * s,
          bY: bY * s,
        ),
      PolylineTo(
        :final x,
        :final y,
        :final vertices,
        :final relative,
        :final vertsRelative,
        :final vertsYRelative,
      ) =>
        PolylineTo(
          x: relative ? x : x * s,
          y: relative ? y : y * s,
          vertices: (vertsRelative && vertsYRelative)
              ? vertices
              : [
                  for (final v in vertices)
                    Offset2D(
                      vertsRelative ? v.x : v.x * s,
                      vertsYRelative ? v.y : v.y * s,
                    ),
                ],
          relative: relative,
          vertsRelative: vertsRelative,
          vertsYRelative: vertsYRelative,
        ),
      InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative) =>
        relative
            ? c
            : InfiniteLineCmd(x: x * s, y: y * s, a: a * s, b: b * s),
      SplineStart(
        :final x,
        :final y,
        :final a,
        :final b,
        :final c,
        :final degree,
        :final relative,
      ) =>
        relative
            ? SplineStart(
                x: x,
                y: y,
                a: a,
                b: b,
                c: c,
                degree: degree,
                relative: true,
              )
            : SplineStart(
                x: x * s,
                y: y * s,
                a: a,
                b: b,
                c: c,
                degree: degree,
              ),
      SplineKnot(:final x, :final y, :final knot, :final relative) =>
        relative
            ? c
            : SplineKnot(x: x * s, y: y * s, knot: knot),
      NurbsTo(
        :final x,
        :final y,
        :final controlPoints,
        :final weights,
        :final knots,
        :final degree,
        :final relative,
        :final cpRelative,
        :final cpYRelative,
      ) =>
        NurbsTo(
          x: relative ? x : x * s,
          y: relative ? y : y * s,
          controlPoints: (cpRelative && cpYRelative)
              ? controlPoints
              : [
                  for (final p in controlPoints)
                    Offset2D(
                      cpRelative ? p.x : p.x * s,
                      cpYRelative ? p.y : p.y * s,
                    ),
                ],
          weights: weights,
          knots: knots,
          degree: degree,
          relative: relative,
          cpRelative: cpRelative,
          cpYRelative: cpYRelative,
        ),
      _ => c,
    };
  }

  void _registerForeignImage(
    _ShapeDraft d,
    Map<String, VsdxImage> images,
    int Function() nextSeq,
  ) {
    final raw = d.foreignBytes;
    if (raw == null || raw.isEmpty) return;
    final decoded = _decodeForeignImage(raw, d.foreignType, d.foreignFormat);
    if (decoded == null) return;
    final seq = nextSeq();
    final part = '/visio/media/image$seq.${decoded.ext}';
    images[part] = VsdxImage(
      partName: part,
      bytes: decoded.bytes,
      mimeType: decoded.mime,
    );
    _foreignPartByShapeId[d.id] = part;
    _foreignTypeByShapeId[d.id] = decoded.foreignType;
  }

  final _foreignPartByShapeId = <int, String>{};
  final _foreignTypeByShapeId = <int, String>{};

  /// Convert Visio ForeignData payload using type/format (libvisio
  /// `VSDContentCollector::_handleForeignData`).
  ({Uint8List bytes, String ext, String mime, String foreignType})?
      _decodeForeignImage(Uint8List raw, int foreignType, int foreignFormat) {
    if (foreignType == 1) {
      switch (foreignFormat) {
        case 0:
        case 255:
          final bmp = _dibToBmp(raw);
          return (
            bytes: bmp,
            ext: 'bmp',
            mime: 'image/bmp',
            foreignType: 'Bitmap',
          );
        case 1:
          return (
            bytes: raw,
            ext: 'jpg',
            mime: 'image/jpeg',
            foreignType: 'Bitmap',
          );
        case 2:
          return (
            bytes: raw,
            ext: 'gif',
            mime: 'image/gif',
            foreignType: 'Bitmap',
          );
        case 3:
          return (
            bytes: raw,
            ext: 'tif',
            mime: 'image/tiff',
            foreignType: 'Bitmap',
          );
        case 4:
          return (
            bytes: raw,
            ext: 'png',
            mime: 'image/png',
            foreignType: 'Bitmap',
          );
      }
    }
    // OLE object (libvisio foreignType 2 → mime `object/ole`).
    if (foreignType == 2 && raw.isNotEmpty) {
      return (
        bytes: raw,
        ext: 'bin',
        mime: 'object/ole',
        foreignType: 'Object',
      );
    }
    // EMF / WMF (libvisio foreignType 0 or 4) — keep bytes for vsdx round-trip;
    // Flutter paints via embedded-bitmap extraction or a placeholder.
    if (foreignType == 0 || foreignType == 4) {
      final isEmf = raw.length > 0x2B &&
          raw[0x28] == 0x20 &&
          raw[0x29] == 0x45 &&
          raw[0x2A] == 0x4D &&
          raw[0x2B] == 0x46;
      if (isEmf) {
        return (
          bytes: raw,
          ext: 'emf',
          mime: 'image/x-emf',
          foreignType: 'EnhMetaFile',
        );
      }
      return (
        bytes: raw,
        ext: 'wmf',
        mime: 'image/x-wmf',
        foreignType: 'MetaFile',
      );
    }
    // Already a self-describing raster (or type unset) — sniff magic.
    final sniff = _sniffImage(raw);
    if (sniff != null) return sniff;
    // Sniff EMF/WMF even when type cell is missing.
    if (raw.length > 0x2B &&
        raw[0x28] == 0x20 &&
        raw[0x29] == 0x45 &&
        raw[0x2A] == 0x4D &&
        raw[0x2B] == 0x46) {
      return (
        bytes: raw,
        ext: 'emf',
        mime: 'image/x-emf',
        foreignType: 'EnhMetaFile',
      );
    }
    if (raw.length >= 4 && raw[0] == 0xd7 && raw[1] == 0xcd) {
      return (
        bytes: raw,
        ext: 'wmf',
        mime: 'image/x-wmf',
        foreignType: 'MetaFile',
      );
    }
    // DIB without BM header (common when format cell missing).
    if (raw.length >= 40) {
      final headerSize = raw[0] |
          (raw[1] << 8) |
          (raw[2] << 16) |
          (raw[3] << 24);
      if (headerSize == 40 || headerSize == 108 || headerSize == 124) {
        final bmp = _dibToBmp(raw);
        return (
          bytes: bmp,
          ext: 'bmp',
          mime: 'image/bmp',
          foreignType: 'Bitmap',
        );
      }
    }
    return null; // unknown foreign payload
  }

  /// Prepend BITMAPFILEHEADER to a DIB (BITMAPINFOHEADER + pixels).
  /// Algorithm reference: libvisio `computeBMPDataOffset` + `_handleForeignData`.
  Uint8List _dibToBmp(Uint8List dib) {
    final dataOff = _bmpDataOffset(dib);
    final total = dib.length + 14;
    final out = Uint8List(total);
    out[0] = 0x42; // 'B'
    out[1] = 0x4D; // 'M'
    out[2] = total & 0xff;
    out[3] = (total >> 8) & 0xff;
    out[4] = (total >> 16) & 0xff;
    out[5] = (total >> 24) & 0xff;
    // reserved 6..9 = 0
    out[10] = dataOff & 0xff;
    out[11] = (dataOff >> 8) & 0xff;
    out[12] = (dataOff >> 16) & 0xff;
    out[13] = (dataOff >> 24) & 0xff;
    out.setRange(14, total, dib);
    return out;
  }

  int _bmpDataOffset(Uint8List dib) {
    if (dib.length < 4) return 14 + 40;
    var headerSize = dib[0] | (dib[1] << 8) | (dib[2] << 16) | (dib[3] << 24);
    if (headerSize > dib.length) headerSize = 40;
    var off = headerSize;
    var bpp = 0;
    if (dib.length >= 16) {
      bpp = dib[14] | (dib[15] << 8);
    }
    if (bpp > 32) bpp = 32;
    const allowed = [1, 4, 8, 16, 24, 32];
    for (final a in allowed) {
      if (bpp <= a) {
        bpp = a;
        break;
      }
    }
    var paletteColors = 0;
    if (dib.length >= 36) {
      paletteColors =
          dib[32] | (dib[33] << 8) | (dib[34] << 16) | (dib[35] << 24);
    }
    if (bpp < 16 && paletteColors == 0) {
      paletteColors = 1 << bpp;
    }
    if (paletteColors > 0 && paletteColors < (dib.length - off) / 4) {
      off += 4 * paletteColors;
    }
    return off + 14; // include BITMAPFILEHEADER
  }

  ({Uint8List bytes, String ext, String mime, String foreignType})?
      _sniffImage(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return (
        bytes: b,
        ext: 'png',
        mime: 'image/png',
        foreignType: 'Bitmap',
      );
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return (
        bytes: b,
        ext: 'jpg',
        mime: 'image/jpeg',
        foreignType: 'Bitmap',
      );
    }
    if (b.length >= 6 &&
        b[0] == 0x47 &&
        b[1] == 0x49 &&
        b[2] == 0x46) {
      return (
        bytes: b,
        ext: 'gif',
        mime: 'image/gif',
        foreignType: 'Bitmap',
      );
    }
    if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) {
      return (
        bytes: b,
        ext: 'bmp',
        mime: 'image/bmp',
        foreignType: 'Bitmap',
      );
    }
    return null;
  }

  List<VsdxShape> _assembleShapes(
    List<_ShapeDraft> drafts, {
    List<int> shapeOrder = const [],
    int defaultDrawingUnit = 0,
  }) {
    final byId = <int, _ShapeDraft>{for (final d in drafts) d.id: d};
    final childrenOf = <int, List<int>>{};
    final roots = <int>[];
    for (final d in drafts) {
      final parent = d.parent;
      if (parent == 0 || parent == _minusOne || !byId.containsKey(parent)) {
        roots.add(d.id);
      } else {
        childrenOf.putIfAbsent(parent, () => <int>[]).add(d.id);
      }
    }

    List<int> orderIds(List<int> ids, List<int> preferred) {
      if (preferred.isEmpty || ids.length <= 1) return ids;
      final remaining = ids.toSet();
      final out = <int>[];
      for (final id in preferred) {
        if (remaining.remove(id)) out.add(id);
      }
      // Append any shapes missing from the order trailer (stable).
      for (final id in ids) {
        if (remaining.remove(id)) out.add(id);
      }
      return out;
    }

    final orderedRoots = orderIds(roots, shapeOrder);

    VsdxShape build(int id) {
      final d = byId[id]!;
      final kids = orderIds(
        childrenOf[id] ?? const <int>[],
        vsdResolveShapeOrder(d.childShapeIds, d.childOrder),
      );
      return _toShape(
        d,
        kids.map(build).toList(),
        defaultDrawingUnit: defaultDrawingUnit,
      );
    }

    return orderedRoots.map(build).toList();
  }

  VsdxShape _toShape(
    _ShapeDraft d,
    List<VsdxShape> children, {
    int defaultDrawingUnit = 0,
  }) {
    if (d.beginTargetId != null) {
      d.formulas['BegTrigger'] =
          '_XFTRIGGER(Sheet.${d.beginTargetId}!EventXFMod)';
    }
    if (d.endTargetId != null) {
      d.formulas['EndTrigger'] =
          '_XFTRIGGER(Sheet.${d.endTargetId}!EventXFMod)';
    }
    final geoms = <VsdxGeometry>[];
    for (var i = 0; i < d.geometries.length; i++) {
      final g = d.geometries[i];
      final cmds = <VsdxPathCommand>[];
      if (g.order.isNotEmpty) {
        for (final id in g.order) {
          final c = g.byId[id];
          if (c != null) cmds.add(c);
        }
      } else {
        // Insertion order by ascending id for stability.
        final ids = g.byId.keys.toList()..sort();
        for (final id in ids) {
          cmds.add(g.byId[id]!);
        }
      }
      if (cmds.isEmpty) continue;
      geoms.add(
        VsdxGeometry(
          commands: cmds,
          noFill: g.noFill,
          noLine: g.noLine,
          noShow: g.noShow,
          ix: i,
        ),
      );
    }

    _applyListOrders(d);
    if (d.legacyTextBytes != null) {
      d.text = _decodeLegacyShapeText(d);
    }
    VsdxRichText rich = const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: libvisioTextBlockStyleDefault,
    );
    final rawText = d.text;
    final textBlock = libvisioTextBlockStyleDefault.copyWith(
      hideText: d.hideText,
      pinXInches: d.txtPinX,
      pinYInches: d.txtPinY,
      widthInches: d.txtWidth,
      heightInches: d.txtHeight,
      locPinXInches: d.txtLocPinX,
      locPinYInches: d.txtLocPinY,
      angleRad: d.txtAngle,
      marginLeftInches: d.marginLeft,
      marginRightInches: d.marginRight,
      marginTopInches: d.marginTop,
      marginBottomInches: d.marginBottom,
      verticalAlign: d.verticalAlign,
      backgroundColor: d.textBgColor,
      defaultTabStopInches: d.defaultTabStop,
      textDirection: d.textDirection,
    );
    final tabSets = [
      for (final t in d.tabRuns)
        VsdxTabSet(ix: t.id, stops: List<VsdxTabStop>.from(t.stops)),
    ];
    String? text;
    if (rawText != null && rawText.trim().isNotEmpty) {
      _reformatNumericFields(d, defaultDrawingUnit: defaultDrawingUnit);
      _finalizeVsd5FieldFormats(d, defaultDrawingUnit: defaultDrawingUnit);
      final textForFields = d.text ?? rawText;
      final built = _buildRichText(d, textForFields, textBlock, tabSets);
      rich = built.rich;
      text = built.plain;
    } else if (d.hideText ||
        d.txtPinX != null ||
        d.txtWidth != null ||
        tabSets.isNotEmpty) {
      rich = VsdxRichText(
        runs: const [],
        textBlock: textBlock,
        tabSets: tabSets,
      );
    }

    final shapeName = d.shapeName ?? 'Sheet.${d.id}';
    final imagePartName = _foreignPartByShapeId[d.id];
    final userProperties = <VsdxUserProperty>[
      for (final p in d.userProperties)
        VsdxUserProperty(
          name: p.name ?? 'Row${p.id}',
          label: p.label,
          value: p.value,
          prompt: p.prompt,
          format: p.format,
          type: p.type,
        ),
    ];
    final userCells = <VsdxUserCell>[
      for (final c in d.userCells)
        VsdxUserCell(
          name: c.name ?? 'Row_${c.id}',
          value: c.value,
          prompt: c.prompt,
        ),
    ];
    bool? containerOverride;
    for (final cell in userCells) {
      if (cell.name == VsdxShape.userContainer) {
        containerOverride = cell.value == '1';
        break;
      }
    }
    final shapeKind = const ShapeKindDetector().detect(
      xmlType: null,
      name: shapeName,
      masterName: null,
      is1D: d.is1D,
      hasImage: imagePartName != null,
      childCount: children.length,
      containerOverride: containerOverride,
      userProperties: userProperties,
    );

    return VsdxShape(
      id: d.id,
      name: shapeName,
      pinX: d.pinX,
      pinY: d.pinY,
      // libvisio preserves zero/negative XForm extents. Missing XFormData
      // therefore stays 0 × 0 instead of becoming an invented unit square.
      width: d.width,
      height: d.height,
      locPinXInches: d.locPinX,
      locPinYInches: d.locPinY,
      angleRad: d.angle,
      flipX: d.flipX,
      flipY: d.flipY,
      locked: d.locked,
      dontMoveChildren: d.dontMoveChildren,
      isTextEditTarget: d.isTextEditTarget,
      selectMode: d.selectMode,
      displayMode: d.displayMode,
      eventDblClick: d.eventDblClick,
      formulas: Map<String, String>.unmodifiable(d.formulas),
      text: text,
      richText: rich,
      fields: _buildFieldRows(d),
      geometries: tagStructuralHitBoxes(geoms),
      fill: d.fill ?? libvisioShapeFillDefault,
      line: d.line ?? VsdxLine.defaultLine,
      shadow: d.shadow ?? VsdxShadow.disabled,
      is1D: d.is1D,
      beginX: d.beginX,
      beginY: d.beginY,
      endX: d.endX,
      endY: d.endY,
      imagePartName: imagePartName,
      imgOffsetXInches: d.imgOffsetX ?? 0,
      imgOffsetYInches: d.imgOffsetY ?? 0,
      imgWidthInches: d.imgWidth,
      imgHeightInches: d.imgHeight,
      foreignType: _foreignTypeByShapeId[d.id],
      layerMemberIds: List<int>.from(d.layerMemberIds),
      connectionPoints: [
        for (final c in d.connectionPoints)
          VsdxConnectionPoint(
            c.x,
            c.y,
            dirX: c.dirX,
            dirY: c.dirY,
            type: c.type,
          ),
      ],
      controls: [
        for (var i = 0; i < d.controls.length; i++)
          VsdxControlRow(
            name: d.controls[i].name ?? 'Row_${i + 1}',
            x: d.controls[i].x,
            y: d.controls[i].y,
            dynX: d.controls[i].dynX,
            dynY: d.controls[i].dynY,
            conX: d.controls[i].conX,
            conY: d.controls[i].conY,
            canGlue: d.controls[i].canGlue,
            prompt: d.controls[i].prompt,
          ),
      ],
      userProperties: userProperties,
      scratch: [
        for (final r in d.scratchRows)
          VsdxScratchRow(
            ix: r.id,
            x: r.x,
            y: r.y,
            a: r.a,
            b: r.b,
            c: r.c,
            d: r.d,
          ),
      ],
      userCells: userCells,
      actions: [
        for (final a in d.actions)
          VsdxActionRow(
            name: a.name ?? 'Row_${a.id}',
            ix: a.id,
            menu: a.menu,
            tag: a.prompt,
          ),
      ],
      hyperlinks: [
        for (final h in d.hyperlinks)
          VsdxHyperlink(
            id: h.id,
            description: h.description,
            address: h.address,
            subAddress: h.subAddress,
            extraInfo: h.extraInfo,
            frame: h.frame,
            newWindow: h.newWindow,
            isDefault: h.isDefault,
            invisible: h.invisible,
          ),
      ],
      children: children,
      shapeKind: shapeKind,
    );
  }

  /// Split shape text into runs by CharIX/ParaIX charCounts (libvisio
  /// `VSDContentCollector` text walk). Field markers expand after the split
  /// so counts stay aligned with the binary stream.
  ({VsdxRichText rich, String plain}) _buildRichText(
    _ShapeDraft d,
    String rawText,
    VsdxTextBlock textBlock,
    List<VsdxTabSet> tabSets,
  ) {
    final chars = d.charRuns;
    final paras = d.paraRuns;
    final tabs = d.tabRuns;

    VsdxCharStyle charStyleOf(_CharRunDraft? c) {
      final bold = c?.bold ?? d.bold;
      final italic = c?.italic ?? d.italic;
      final smallCaps = c?.smallCaps ?? d.smallCaps;
      return VsdxCharStyle(
        fontFamily: c?.fontFamily ?? d.fontFamily ?? 'Arial',
        fontSizeInches: c?.fontSizeInches ?? d.fontSizeInches ?? (12.0 / 72.0),
        color:
            c?.textColor ?? d.textColor ?? libvisioCharacterStyleDefault.color,
        style: VsdxFontStyle(
          bold: bold,
          italic: italic,
          smallCaps: smallCaps,
        ),
        underline: c?.underline ?? d.underline,
        textCase: c?.textCase ?? d.textCase,
        position: c?.textPosition ?? d.textPosition,
        strikethrough: c?.strikethrough ?? d.strikethrough,
        doubleUnderline: c?.doubleUnderline ?? d.doubleUnderline,
        doubleStrikethrough: c?.doubleStrikethrough ?? d.doubleStrikethrough,
        fontScale: c?.fontScale ?? d.fontScale,
      );
    }

    VsdxParaStyle paraStyleOf(_ParaRunDraft? p) {
      var lineSpacing = libvisioParagraphStyleDefault.lineSpacing;
      var lineSpacingAbs = 0.0;
      var lineSpacingSolid = false;
      final sp = p?.spLine ?? d.spLine;
      if (sp != null) {
        if (sp < 0) {
          lineSpacing = -sp;
        } else if (sp == 0) {
          lineSpacingSolid = true;
        } else {
          lineSpacingAbs = sp;
        }
      }
      return VsdxParaStyle(
        horizontalAlign: p?.paraAlign ??
            d.paraAlign ??
            libvisioParagraphStyleDefault.horizontalAlign,
        indentFirstInches: p?.indFirst ?? d.indFirst ?? 0.0,
        indentLeftInches: p?.indLeft ?? d.indLeft ?? 0.0,
        indentRightInches: p?.indRight ?? d.indRight ?? 0.0,
        spaceBeforeInches: p?.spBefore ?? d.spBefore ?? 0.0,
        spaceAfterInches: p?.spAfter ?? d.spAfter ?? 0.0,
        lineSpacing: lineSpacing,
        lineSpacingAbsoluteInches: lineSpacingAbs,
        lineSpacingSolid: lineSpacingSolid,
        bullet: p?.bullet ?? d.bullet ?? 0,
        bulletStr: p?.bulletStr ?? d.bulletStr,
        bulletFont: p?.bulletFont ?? d.bulletFont,
        bulletFontSizeInches: p?.bulletFontSize ?? d.bulletFontSize,
        textPosAfterBulletInches:
            p?.textPosAfterBullet ?? d.textPosAfterBullet ?? 0.0,
        flags: p?.paraFlags ?? d.paraFlags ?? 0,
      );
    }

    // Single-run fast path when there is at most one CharIX/ParaIX.
    final multi = chars.length > 1 || paras.length > 1;
    if (!multi) {
      final expanded = d.fieldDisplays.isEmpty
          ? (text: rawText, spans: const <VsdxFieldSpan>[])
          : _expandFieldMarkers(d, rawText);
      final trimmed = _trimFieldExpansion(expanded.text, expanded.spans);
      final plain = trimmed.text;
      return (
        rich: VsdxRichText(
          runs: [
            VsdxTextRun(
              text: plain,
              charStyle: charStyleOf(chars.isEmpty ? null : chars.first),
              paraStyle: paraStyleOf(paras.isEmpty ? null : paras.first),
              fieldSpans: trimmed.spans,
            ),
          ],
          textBlock: textBlock,
          tabSets: tabSets,
        ),
        plain: plain,
      );
    }

    var ci = 0;
    var pi = 0;
    var ti = 0;
    var charLeft = chars.isEmpty ? rawText.length : chars.first.charCount;
    var paraLeft = paras.isEmpty ? rawText.length : paras.first.charCount;
    var tabLeft = tabs.isEmpty ? rawText.length : tabs.first.numChars;
    if (charLeft == 0 && chars.isNotEmpty) charLeft = rawText.length;
    if (paraLeft == 0 && paras.isNotEmpty) paraLeft = rawText.length;
    if (tabLeft == 0 && tabs.isNotEmpty) tabLeft = rawText.length;

    final runs = <VsdxTextRun>[];
    final buf = StringBuffer();
    final fieldSpans = <VsdxFieldSpan>[];
    final tabIndices = <int>[];
    var fieldIdx = 0;
    var prevCi = -1;
    var prevPi = -1;
    VsdxCharStyle curChar = charStyleOf(null);
    VsdxParaStyle curPara = paraStyleOf(null);

    void flush() {
      if (buf.isEmpty && fieldSpans.isEmpty) return;
      runs.add(VsdxTextRun(
        text: buf.toString(),
        charStyle: curChar,
        paraStyle: curPara,
        fieldSpans: List<VsdxFieldSpan>.from(fieldSpans),
        tabIndices: List<int>.from(tabIndices),
      ));
      buf.clear();
      fieldSpans.clear();
      tabIndices.clear();
    }

    for (var i = 0; i < rawText.length; i++) {
      if (ci != prevCi || pi != prevPi) {
        flush();
        curChar = charStyleOf(chars.isEmpty ? null : chars[ci]);
        curPara = paraStyleOf(paras.isEmpty ? null : paras[pi]);
        prevCi = ci;
        prevPi = pi;
      }

      final cu = rawText.codeUnitAt(i);
      if (cu == 0xFFFC || cu == 0x1E) {
        if (fieldIdx < d.fieldDisplays.length) {
          final display = d.fieldDisplays[fieldIdx];
          final start = buf.length;
          buf.write(display);
          fieldSpans.add(VsdxFieldSpan(
            start: start,
            length: display.length,
            ix: _fieldIx(d, fieldIdx),
          ));
          fieldIdx++;
        }
      } else {
        buf.writeCharCode(cu);
        if (cu == 0x09 && tabs.isNotEmpty) {
          tabIndices.add(tabs[ti].id);
        }
      }

      if (charLeft > 0) charLeft--;
      if (charLeft == 0 && ci + 1 < chars.length) {
        ci++;
        charLeft = chars[ci].charCount;
        if (charLeft == 0) charLeft = rawText.length - i;
      }
      if (paraLeft > 0) paraLeft--;
      if (paraLeft == 0 && pi + 1 < paras.length) {
        pi++;
        paraLeft = paras[pi].charCount;
        if (paraLeft == 0) paraLeft = rawText.length - i;
      }
      if (tabLeft > 0) tabLeft--;
      if (tabLeft == 0 && ti + 1 < tabs.length) {
        ti++;
        tabLeft = tabs[ti].numChars;
        if (tabLeft == 0) tabLeft = rawText.length - i;
      }
    }
    flush();

    if (runs.isEmpty) {
      final plain = rawText.trim();
      return (
        rich: VsdxRichText(
          runs: [
            VsdxTextRun(
              text: plain,
              charStyle: charStyleOf(null),
              paraStyle: paraStyleOf(null),
            ),
          ],
          textBlock: textBlock,
          tabSets: tabSets,
        ),
        plain: plain,
      );
    }

    final plain = runs.map((r) => r.text).join().trim();
    return (
      rich: VsdxRichText(
        runs: runs,
        textBlock: textBlock,
        tabSets: tabSets,
      ),
      plain: plain,
    );
  }
}
