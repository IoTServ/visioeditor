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
}
