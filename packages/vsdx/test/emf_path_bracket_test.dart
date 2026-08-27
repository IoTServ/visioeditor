import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _pathBracketEmf({
  int paintRecord = 63,
  int fillMode = 1,
  bool abort = false,
  bool restoreBeforeInner = false,
  bool roundedOuter = false,
}) {
  final out = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void pointRecord(int type, int x, int y) {
    u32(type);
    u32(16);
    i32(x);
    i32(y);
  }

  void emptyRecord(int type) {
    u32(type);
    u32(8);
  }

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add(const <int>[0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }

  // Solid red brush at handle 1.
  u32(39); // EMR_CREATEBRUSHINDIRECT
  u32(24);
  u32(1);
  u32(0); // BS_SOLID
  u32(0x000000FF); // COLORREF red
  u32(0);
  u32(37); // EMR_SELECTOBJECT
  u32(12);
  u32(1);
  u32(19); // EMR_SETPOLYFILLMODE
  u32(12);
  u32(fillMode);

  emptyRecord(59); // EMR_BEGINPATH
  if (roundedOuter) {
    u32(44); // EMR_ROUNDRECT
    u32(32);
    i32(10);
    i32(10);
    i32(90);
    i32(90);
    u32(20); // Corner ellipse width.
    u32(20); // Corner ellipse height.
  } else {
    pointRecord(27, 10, 10);
    pointRecord(54, 90, 10);
    pointRecord(54, 90, 90);
    pointRecord(54, 10, 90);
    emptyRecord(61); // EMR_CLOSEFIGURE
  }

  if (restoreBeforeInner) emptyRecord(33); // EMR_SAVEDC

  // Inner contour has the same orientation as the outer contour. ALTERNATE
  // leaves a hole; WINDING fills it.
  pointRecord(27, 30, 30);
  pointRecord(54, 70, 30);
  pointRecord(54, 70, 70);
  pointRecord(54, 30, 70);
  emptyRecord(61);
  if (restoreBeforeInner) {
    u32(34); // EMR_RESTOREDC
    u32(12);
    i32(-1);
  }

  if (abort) {
    emptyRecord(68); // EMR_ABORTPATH
    // A later ordinary record must still render.
    pointRecord(27, 5, 5);
    pointRecord(54, 95, 95);
  } else {
    emptyRecord(60); // EMR_ENDPATH
    u32(paintRecord);
    u32(24);
    i32(10);
    i32(10);
    i32(90);
    i32(90);
  }

  u32(14);
  u32(20);
  u32(0);
  u32(16);
  u32(20);
  return Uint8List.fromList(out.toBytes());
}

VsdxPage _picturePage(String part) => VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );

void main() {
  test('EMF path brackets retain compound contours and paint modes', () {
    for (final entry in <(int, bool, bool)>[
      (62, false, true), // FILLPATH
      (63, true, true), // STROKEANDFILLPATH
      (64, true, false), // STROKEPATH
    ]) {
      final drawing = parseEmfDrawing(_pathBracketEmf(paintRecord: entry.$1));
      expect(drawing, isNotNull);
      final path = drawing!.ops.whereType<MetafilePathOp>().single;
      expect(path.stroke, entry.$2);
      expect(path.fill, entry.$3);
      expect(path.closed, isTrue);
      expect(path.additionalContours, hasLength(1));
      expect(path.additionalContours.single.closed, isTrue);
      expect(path.evenOddFill, isTrue);
    }
  });

  test('EMF compound path reaches SVG with its GDI fill rule', () {
    const part = '/visio/media/path-bracket.emf';
    final bytes = _pathBracketEmf();
    final page = _picturePage(part);
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: bytes,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(svg, contains('fill-rule="evenodd"'));
    expect(svg, contains('fill="#ff0000"'));
    expect(RegExp(r'M 10 10.*Z M 30 30.*Z').hasMatch(svg), isTrue);

    final windingBytes = _pathBracketEmf(fillMode: 2);
    final windingImages = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: windingBytes,
      mimeType: 'image/x-emf',
    ));
    final windingSvg =
        VsdxToSvgSerializer().serializePage(page, images: windingImages);
    expect(windingSvg, isNot(contains('fill-rule="evenodd"')));
  });

  test('EMF ABORTPATH discards cached figures without aborting the file', () {
    final drawing = parseEmfDrawing(_pathBracketEmf(abort: true));
    expect(drawing, isNotNull);
    final path = drawing!.ops.whereType<MetafilePathOp>().single;
    expect(path.additionalContours, isEmpty);
    expect((path.points.first.x, path.points.first.y), (5, 5));
    expect((path.points.last.x, path.points.last.y), (95, 95));
  });

  test('EMF RestoreDC restores the saved path figures', () {
    final drawing = parseEmfDrawing(_pathBracketEmf(restoreBeforeInner: true));
    expect(drawing, isNotNull);
    final path = drawing!.ops.whereType<MetafilePathOp>().single;
    expect(path.additionalContours, isEmpty);
    expect(path.points, hasLength(4));
    expect(path.fill, isTrue);
    expect(path.stroke, isTrue);
  });

  test('EMF path bracket keeps ROUNDRECT corner geometry', () {
    final drawing = parseEmfDrawing(_pathBracketEmf(roundedOuter: true));
    expect(drawing, isNotNull);
    final path = drawing!.ops.whereType<MetafilePathOp>().single;
    expect(path.closed, isTrue);
    expect(path.points.length, greaterThan(8));
    expect(path.points.any((point) => point.x == 10 && point.y == 10), isFalse,
        reason: 'rounded corners must not collapse to the bounding rectangle');
  });

  test('EMF path bracket bytes survive VSDX write and reopen', () {
    const part = '/visio/media/path-bracket.emf';
    final payload = _pathBracketEmf();
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    const parser = DocumentParser();
    var document = parser.parse(blank);
    final page = document.pages.first;
    final picture = VsdxShapeFactory.picture(
      id: page.nextFreeShapeId(),
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      imagePartName: part,
    ).copyWith(foreignType: 'EnhMetaFile');
    document = document
        .copyWith(
          images: document.images.withImage(VsdxImage(
            partName: part,
            bytes: payload,
            mimeType: 'image/x-emf',
          )),
        )
        .replacePage(0, page.addShape(picture));

    final saved = writer.write(originalBytes: blank, edited: document);
    final reopened = parser.parse(saved);
    final reopenedImage = reopened.images.findByPart(part)!;
    expect(reopenedImage.bytes, payload);
    expect(parseEmfDrawing(reopenedImage.bytes), isNotNull);
  });
}
