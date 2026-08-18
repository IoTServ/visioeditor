import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/font_fallback.dart';

void main() {
  const fallback = VsdxFontFallback.defaults;

  test('serif Visio faces retain a serif fallback class', () {
    final times = fallback.resolve(
      'Times New Roman',
      platformOverride: 'linux',
    );
    final cambria = fallback.resolve('Cambria', platformOverride: 'mac');

    expect(times.family, 'Times New Roman');
    expect(times.familyFallback.take(2), <String>[
      'Liberation Serif',
      'DejaVu Serif',
    ]);
    expect(
      cambria.familyFallback,
      containsAllInOrder(<String>['Times', 'serif']),
    );
    expect(
      times.familyFallback.indexOf('DejaVu Serif'),
      lessThan(times.familyFallback.indexOf('DejaVu Sans')),
    );
  });

  test('monospace Visio faces retain a fixed-width fallback class', () {
    final courier = fallback.resolve('Courier New', platformOverride: 'linux');
    final consolas = fallback.resolve('Consolas', platformOverride: 'mac');

    expect(courier.family, 'Courier New');
    expect(courier.familyFallback.take(2), <String>[
      'Liberation Mono',
      'DejaVu Sans Mono',
    ]);
    expect(
      consolas.familyFallback,
      containsAllInOrder(<String>['Menlo', 'Monaco', 'monospace']),
    );
    expect(
      courier.familyFallback.indexOf('DejaVu Sans Mono'),
      lessThan(courier.familyFallback.indexOf('DejaVu Sans')),
    );
  });

  test('sans and script-specific fallback ordering stays unchanged', () {
    final resolved = fallback.resolve(
      'Calibri',
      asianFont: 'Microsoft YaHei',
      complexScriptFont: 'Tahoma',
      platformOverride: 'linux',
    );

    expect(resolved.family, 'Calibri');
    expect(resolved.familyFallback.take(4), <String>[
      'Microsoft YaHei',
      'Tahoma',
      'Liberation Sans',
      'DejaVu Sans',
    ]);
  });
}
