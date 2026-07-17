// Translates Chinese labels in assets/examples/workflow.vsdx to English.
//
// Run from the project root:
//   dart run tool/translate_workflow_example.dart
import 'dart:io';

import 'package:vsdx/vsdx.dart';

const String kPath = 'assets/examples/workflow.vsdx';

/// Shape id → English label (newlines preserved where the original wrapped).
const Map<int, String> kTranslations = <int, String>{
  102: 'Marketing request',
  103: 'User feedback',
  104: 'Business feedback',
  105: 'Company strategy',
  106: 'Product R&D',
  107: 'Brief requirements',
  108: 'Product team',
  114: 'Feasible?',
  115: 'Tech / product /\nbusiness discussion',
  116: 'Approve project',
  117: 'Analyse clauses',
  119: 'Tech / product / business\nreview requirements',
  121: 'Yes',
  125: 'Meets\nrequirements?',
  126: 'No',
  128: 'Refine requirements',
  129: 'Yes',
  130: 'Content review\npassed?',
  132: 'Engineering review',
  133: 'Yes',
  135: 'Coordinate content prep',
  137: 'Development',
  138: 'QA found\nbugs?',
  139: 'Yes',
  142: 'Load baseline test data',
  143: 'No',
  144: 'Update tech docs',
  146: 'Record rejection reasons',
  148: 'Realistic testing',
  149: 'Passed?',
  150: 'Prepare internal\nbriefing docs',
  151: 'Yes',
  152: 'No',
  155: 'Internal briefing',
  156: 'Internal test\nOK?',
  157: 'Pass',
  160: 'Yes',
  161: 'No',
  166: 'No',
  167: 'Start',
  168: 'End',
};

void main() {
  final bytes = File(kPath).readAsBytesSync();
  final writer = const VsdxWriter();
  final parser = DocumentParser();
  var doc = parser.parse(bytes);
  final page = doc.pages.first;
  var next = page;
  var changed = 0;
  for (final e in kTranslations.entries) {
    final s = next.findShapeById(e.key);
    if (s == null) {
      stderr.writeln('missing shape ${e.key}');
      continue;
    }
    final rich = replacePlainText(s.richText, e.value);
    next = next.updateShapeById(
      e.key,
      (sh) => sh.copyWith(text: e.value, richText: rich),
    );
    changed++;
  }
  // Clear empty page name so the UI shows a sensible default after open.
  if (next.name.trim().isEmpty) {
    next = next.copyWith(name: 'Workflow');
  }
  doc = doc
      .replacePage(0, next)
      .copyWith(title: 'Workflow', creator: 'Editor for Visio Diagrams');
  final out = writer.write(originalBytes: bytes, edited: doc);
  File(kPath).writeAsBytesSync(out);
  stdout.writeln('updated $kPath ($changed labels)');
}
