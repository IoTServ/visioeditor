import 'dart:io';
import 'dart:typed_data';
import 'package:vsdx/vsdx.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : 'test/fixtures/workflow.vsdx';
  final out = args.length > 1 ? args[1] : '/tmp/workflow.svg';
  final bytes = Uint8List.fromList(File(path).readAsBytesSync());
  final doc = const DocumentParser().parse(bytes);
  final svg = VsdxToSvgSerializer().serializeDocument(doc);
  File(out).writeAsStringSync(svg);
  stdout.writeln('wrote $out (${svg.length} bytes), pages=${doc.pages.length}');
}
