import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vsdxtool_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  void writeTwoPageDocument(String path) {
    final original = const VsdxWriter().emptyDocument();
    var doc = const DocumentParser().parse(original);
    final first = doc.pages.first.copyWith(
      shapes: <VsdxShape>[
        withLabel(
          VsdxShapeFactory.rectangle(
            id: 1,
            pinX: 2,
            pinY: 2,
            width: 1,
            height: 1,
          ),
          'First page',
        ),
      ],
    );
    final second = VsdxPage(
      id: doc.nextPageId(),
      name: 'Page-2',
      widthInches: first.widthInches,
      heightInches: first.heightInches,
      shapes: <VsdxShape>[
        withLabel(
          VsdxShapeFactory.rectangle(
            id: 1,
            pinX: 4,
            pinY: 4,
            width: 1,
            height: 1,
          ),
          'Second page',
        ),
      ],
    );
    doc = doc.copyWith(pages: <VsdxPage>[first, second]);
    File(path).writeAsBytesSync(
      const VsdxWriter().write(originalBytes: original, edited: doc),
    );
  }

  Future<ProcessResult> patch(
    String drawing,
    List<Map<String, dynamic>> ops, {
    int page = 0,
  }) {
    final opsPath = '${tmp.path}/ops.json';
    File(opsPath).writeAsStringSync(jsonEncode(<String, dynamic>{'ops': ops}));
    return Process.run(
      Platform.resolvedExecutable,
      <String>[
        'run',
        'bin/vsdxtool.dart',
        'patch',
        '--input',
        drawing,
        '--ops',
        opsPath,
        '--page',
        '$page',
      ],
      workingDirectory: Directory.current.path,
    );
  }

  test('patch --page edits that page and leaves other page untouched',
      () async {
    final path = '${tmp.path}/pages.vsdx';
    writeTwoPageDocument(path);

    final result = await patch(
      path,
      <Map<String, dynamic>>[
        <String, dynamic>{
          'op': 'set_text',
          'id': 1,
          'text': 'CLI second page',
        },
      ],
      page: 1,
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('patched'));
    expect('${result.stdout}', contains('page 1'));
    final pages =
        const DocumentParser().parse(File(path).readAsBytesSync()).pages;
    expect(pages[0].findShapeById(1)!.text, 'First page');
    expect(pages[1].findShapeById(1)!.text, 'CLI second page');
  });

  test('rejected in-place patch does not rewrite the file', () async {
    final path = '${tmp.path}/no-op.vsdx';
    writeTwoPageDocument(path);
    final file = File(path);
    final fixed = DateTime.utc(2002, 3, 4, 5, 6, 7);
    file.setLastModifiedSync(fixed);

    final result = await patch(path, <Map<String, dynamic>>[
      <String, dynamic>{'op': 'delete_shape', 'id': 999999},
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', startsWith('no changes to'));
    expect('${result.stdout}',
        contains('skipped: delete_shape: shape 999999 not found'));
    expect(file.lastModifiedSync(), fixed.toLocal());
  });
}
