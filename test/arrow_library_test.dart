import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/arrow_library.dart';

/// Guards the arrowhead ids exercised by the 人才招聘冰山模型 / 数据治理 fixtures,
/// which regressed before: id 10 drew a diamond (should be a filled ball) and
/// id 12 drew a one-sided half-triangle (should be a full concave/stealth
/// arrow). See `lib/render/arrow_library.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('id 10 is a filled circle (ball), not a diamond', () {
    final d = arrowDescriptor(10)!;
    expect(d.filled, isTrue);
    final b = d.path.getBounds();
    // A circle has (near) square bounds — a diamond is wider than tall.
    expect(b.width, closeTo(b.height, 0.02));
    // Round, not a polygon: the bounding-box corners fall outside the fill…
    expect(d.path.contains(b.topLeft), isFalse);
    expect(d.path.contains(b.bottomRight), isFalse);
    // …while the centre is inside.
    expect(d.path.contains(b.center), isTrue);
  });

  test('id 12 is a full concave/stealth arrow, not a half-triangle', () {
    final d = arrowDescriptor(12)!;
    expect(d.filled, isTrue);
    final b = d.path.getBounds();
    // Symmetric about the line axis (the half-arrow bug had one edge on y=0).
    expect(b.top, lessThan(-0.2));
    expect(b.bottom, greaterThan(0.2));
    expect(b.top, closeTo(-b.bottom, 0.02));
    // Concave back: the mid-back point sits inside the outer barbs, so the
    // fill does NOT reach the middle of the base edge.
    expect(d.path.contains(Offset(b.left + 0.02, 0)), isFalse);
  });

  test('id 4 stays a filled triangle', () {
    final d = arrowDescriptor(4)!;
    expect(d.filled, isTrue);
    final b = d.path.getBounds();
    expect(b.top, closeTo(-b.bottom, 0.02));
    // Solid triangle: the middle of the base edge is filled (unlike stealth).
    expect(d.path.contains(Offset(b.left + 0.02, 0)), isTrue);
  });
}
