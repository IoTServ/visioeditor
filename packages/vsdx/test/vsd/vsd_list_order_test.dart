import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_parser.dart';

void main() {
  group('vsdReorderById', () {
    test('reorders when trailer differs from encounter order', () {
      final items = [
        (id: 10, label: 'a'),
        (id: 20, label: 'b'),
        (id: 30, label: 'c'),
      ];
      final ordered = vsdReorderById(items, [30, 10, 20], (e) => e.id);
      expect([for (final e in ordered) e.label], ['c', 'a', 'b']);
    });

    test('keeps encounter order when trailer is empty', () {
      final items = [
        (id: 1, label: 'x'),
        (id: 2, label: 'y'),
      ];
      final ordered = vsdReorderById(items, const [], (e) => e.id);
      expect([for (final e in ordered) e.label], ['x', 'y']);
    });

    test('appends items missing from trailer at the end', () {
      final items = [
        (id: 1, label: 'a'),
        (id: 2, label: 'b'),
        (id: 3, label: 'c'),
      ];
      final ordered = vsdReorderById(items, [2], (e) => e.id);
      expect([for (final e in ordered) e.label], ['b', 'a', 'c']);
    });

    test('ignores unknown trailer ids and duplicate ids', () {
      final items = [
        (id: 1, label: 'a'),
        (id: 2, label: 'b'),
      ];
      final ordered = vsdReorderById(items, [99, 2, 2, 1], (e) => e.id);
      expect([for (final e in ordered) e.label], ['b', 'a']);
    });
  });
}
