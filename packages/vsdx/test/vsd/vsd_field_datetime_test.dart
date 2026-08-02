import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_parser.dart';

void main() {
  final value = DateTime.utc(1982, 4, 19, 22, 2, 3);

  test('legacy time formats preserve seconds and meridiem', () {
    expect(vsdFormatVisioTimeField(value, 30), '10:02:03 PM');
    for (final format in [31, 32, 33, 34]) {
      expect(vsdFormatVisioTimeField(value, format), '22:02:03');
    }
    for (final format in [35, 36]) {
      expect(vsdFormatVisioTimeField(value, format), '10:02 PM');
    }
  });

  test('East Asian time formats do not fall through to calendar dates', () {
    for (final format in [
      46,
      66,
      67,
      68,
      69,
      70,
      71,
      72,
      73,
      74,
      75,
      80,
      81,
    ]) {
      expect(vsdFormatVisioTimeField(value, format), '22:02:03');
    }
  });

  test('Microsoft date and time formats retain their full time shape', () {
    expect(
      vsdFormatVisioTimeField(value, 211),
      '04/19/1982 10:02 PM',
    );
    expect(
      vsdFormatVisioTimeField(value, 212),
      '04/19/1982 10:02:03 PM',
    );
    expect(vsdFormatVisioTimeField(value, 213), '10:02 PM');
    expect(vsdFormatVisioTimeField(value, 214), '10:02:03 PM');
    expect(vsdFormatVisioTimeField(value, 215), '22:02');
    expect(vsdFormatVisioTimeField(value, 216), '22:02:03');
  });

  test('non-time formats remain available to the date formatter', () {
    expect(vsdFormatVisioTimeField(value, 200), isNull);
    expect(vsdFormatVisioTimeField(value, 0xffff), isNull);
  });
}
