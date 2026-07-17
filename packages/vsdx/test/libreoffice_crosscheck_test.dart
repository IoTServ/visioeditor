import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

/// Optional LibreOffice headless cross-check.
///
/// Skips when `soffice` / `libreoffice` is not on PATH and `SOFFICE` is unset,
/// unless `REQUIRE_SOFFICE=1` (CI) — then missing soffice fails the test.
///
/// When available, writes a round-tripped `.vsdx` and asks soffice to convert
/// it to PDF (proves LibreOffice can open the package).
void main() {
  final soffice = _resolveSoffice();
  final require = Platform.environment['REQUIRE_SOFFICE'] == '1';

  test('LibreOffice soffice opens a writer round-trip .vsdx', () async {
    if (soffice == null) {
      if (require) {
        fail('REQUIRE_SOFFICE=1 but LibreOffice soffice was not found '
            '(set SOFFICE or install LibreOffice)');
      }
      // ignore: avoid_print
      print('skip: LibreOffice soffice not installed '
          '(set SOFFICE or install LibreOffice)');
      return;
    }

    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 3,
          width: 2,
          height: 1,
          name: 'Box',
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Hello LO')],
          ),
        ),
      ),
    );
    final vsdxBytes = writer.write(originalBytes: blank, edited: doc);

    final dir = await Directory.systemTemp.createTemp('vsdx_lo_');
    final profile = Directory('${dir.path}/lo_profile')..createSync();
    try {
      final input = File('${dir.path}/in.vsdx');
      await input.writeAsBytes(vsdxBytes);
      final result = await Process.run(
        soffice,
        <String>[
          '--headless',
          '--norestore',
          '--nofirststartwizard',
          '-env:UserInstallation=file://${profile.path}',
          '--convert-to',
          'pdf',
          '--outdir',
          dir.path,
          input.path,
        ],
        workingDirectory: dir.path,
        environment: <String, String>{
          ...Platform.environment,
          // Prefer headless VCL on Linux CI runners.
          'SAL_USE_VCLPLUGIN': 'svp',
        },
      );
      expect(result.exitCode, 0,
          reason: 'soffice stderr: ${result.stderr}\nstdout: ${result.stdout}');

      final pdf = File('${dir.path}/in.pdf');
      expect(pdf.existsSync(), isTrue,
          reason: 'expected in.pdf from soffice convert-to pdf; '
              'dir=${dir.listSync().map((e) => e.path).toList()}');
      expect(pdf.lengthSync(), greaterThan(100));

      // Still parseable as a package after our write (independent of LO).
      final reparsed = parser.parse(vsdxBytes);
      expect(reparsed.pages, isNotEmpty);
      expect(reparsed.pages.first.shapes, isNotEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  },
      skip: (!require && soffice == null)
          ? 'LibreOffice soffice not installed'
          : false);
}

String? _resolveSoffice() {
  final env = Platform.environment['SOFFICE'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  for (final name in <String>['soffice', 'libreoffice']) {
    final which = Process.runSync('which', <String>[name]);
    if (which.exitCode == 0) {
      final path = (which.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  }
  const mac =
      '/Applications/LibreOffice.app/Contents/MacOS/soffice';
  if (File(mac).existsSync()) return mac;
  return null;
}
