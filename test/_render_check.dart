import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render workflow to png for visual check', () async {
    final bytes =
        Uint8List.fromList(File('assets/examples/workflow.vsdx').readAsBytesSync());
    final doc = const DocumentParser().parse(bytes);
    final png = await renderPageToPng(
      doc.pages.first,
      theme: doc.theme,
      images: doc.images,
      pxPerInch: 120,
    );
    expect(png, isNotNull);
    File('/tmp/workflow_app.png').writeAsBytesSync(png!);
  });
}
