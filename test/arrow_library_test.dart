import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/arrow_library.dart';

/// Guards the Visio line-end ids against libvisio's marker table.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('id 10 is a filled circle (ball), not a diamond', () {
    final d = arrowDescriptor(10)!;
    expect(d.filled, isTrue);
    expect(d.centered, isTrue);
    final b = d.path.getBounds();
    // A circle has (near) square bounds — a diamond is wider than tall.
    expect(b.width, closeTo(b.height, 0.02));
    // Round, not a polygon: the bounding-box corners fall outside the fill…
    expect(d.path.contains(b.topLeft), isFalse);
    expect(d.path.contains(b.bottomRight), isFalse);
    // …while the centre is inside.
    expect(d.path.contains(b.center), isTrue);
  });

  test('id 12 is an open long arrowhead', () {
    final d = arrowDescriptor(12)!;
    expect(d.filled, isFalse);
    final b = d.path.getBounds();
    // Symmetric about the line axis, with a swept-back centre.
    expect(b.top, lessThan(-0.2));
    expect(b.bottom, greaterThan(0.2));
    expect(b.top, closeTo(-b.bottom, 0.02));
  });

  test('id 4 stays a filled triangle', () {
    final d = arrowDescriptor(4)!;
    expect(d.filled, isTrue);
    final b = d.path.getBounds();
    expect(b.top, closeTo(-b.bottom, 0.02));
    // Solid triangle: the middle of the base edge is filled (unlike stealth).
    expect(d.path.contains(Offset(b.left + 0.02, 0)), isTrue);
  });

  test('all libvisio marker ids 0 through 45 are implemented', () {
    expect(supportedArrowIds().toSet(), containsAll(<int>{
      for (var id = 0; id <= 45; id++) id,
    }));
  });

  test('id 13 keeps libvisio long-triangle proportions', () {
    final marker = arrowDescriptor(13)!;
    final bounds = marker.path.getBounds();
    expect(marker.filled, isTrue);
    expect(bounds.width, closeTo(1.4, 1e-6));
    expect(bounds.height / bounds.width, closeTo(2 / 3, 1e-6));
  });

  test('ids 11/20/22 match square, open circle and open diamond', () {
    final square = arrowDescriptor(11)!;
    final circle = arrowDescriptor(20)!;
    final diamond = arrowDescriptor(22)!;
    expect(square.filled, isTrue);
    expect(square.path.getBounds().width, greaterThan(0.7));
    expect(circle.filled, isFalse);
    expect(circle.path.contains(circle.path.getBounds().center), isTrue);
    expect(diamond.filled, isFalse);
    expect(diamond.path.getBounds().width, greaterThan(0.9));
  });

  test('id 23 keeps libvisio oblique stroke and centred stem', () {
    final marker = arrowDescriptor(23)!;
    final bounds = marker.path.getBounds();
    expect(marker.filled, isFalse);
    expect(bounds.width, closeTo(1, 0.02));
    expect(bounds.height, closeTo(1, 0.02));
  });

  test('crow-foot markers extend beyond rather than into the endpoint', () {
    for (final id in <int>[27, 28, 29, 30]) {
      final bounds = arrowDescriptor(id)!.path.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(0), reason: 'marker $id');
      expect(bounds.right, greaterThan(0), reason: 'marker $id');
    }
  });

  test('id 9 keeps libvisio dimension-tick viewBox overflow', () {
    final marker = arrowDescriptor(9)!;
    final bounds = marker.path.getBounds();
    expect(marker.filled, isFalse);
    expect(marker.centered, isTrue);
    expect(bounds.width, closeTo(1, 0.02));
    expect(bounds.height, closeTo(2.2, 0.02));
  });

  test('libvisio TODO aliases keep their upstream marker paths', () {
    expect(arrowDescriptor(40)!.filled, isTrue);
    for (final id in <int>[43, 44, 45]) {
      final marker = arrowDescriptor(id)!;
      expect(marker.filled, isFalse, reason: 'marker $id');
      expect(marker.path.getBounds(), arrowDescriptor(3)!.path.getBounds());
    }
  });

  test('only libvisio marker-center ids are centred', () {
    for (final id in <int>[9, 10, 11, 20, 21]) {
      expect(arrowDescriptor(id)!.centered, isTrue, reason: 'marker $id');
    }
    for (final id in <int>[31, 41, 42]) {
      expect(arrowDescriptor(id)!.centered, isFalse, reason: 'marker $id');
    }
  });

  test('id 34 aliases the full open-circle path like libvisio', () {
    final marker34 = arrowDescriptor(34)!;
    final marker33 = arrowDescriptor(33)!;
    expect(marker34.filled, isFalse);
    expect(marker34.centered, isFalse);
    expect(marker34.path.getBounds(), marker33.path.getBounds());
  });

  test('non-centred markers trim the body but centred markers do not', () {
    expect(arrowBodyTrimInches(31, 0.25, 0.04), closeTo(0.23, 1e-9));
    expect(arrowBodyTrimInches(39, 0.25, 0.04), closeTo(0.28, 1e-6));
    expect(arrowBodyTrimInches(20, 0.25, 0.04), 0);
    expect(arrowBodyTrimInches(27, 0.25, 0.04), 0);
  });

  test('ids 35–37 put the bar before the filled circle', () {
    final marker = arrowDescriptor(35)!;
    expect(marker.path.contains(const Offset(-0.9, 0.45)), isTrue);
    expect(marker.path.contains(const Offset(-0.02, 0.45)), isFalse);
    expect(marker.path.getBounds(), arrowDescriptor(37)!.path.getBounds());
  });

  test('id 7 aliases the open-chevron path of id 19 like libvisio', () {
    final marker7 = arrowDescriptor(7)!;
    final marker19 = arrowDescriptor(19)!;
    expect(marker7.filled, isFalse);
    expect(marker7.centered, isFalse);
    expect(marker7.path.getBounds(), marker19.path.getBounds());
    expect(arrowDebugReach(7), arrowDebugReach(19));
  });
}
