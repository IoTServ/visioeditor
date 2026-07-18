import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('extractImports', () {
    test('dart import/export specifiers', () {
      final imps = extractImports('''
import 'dart:io';
import 'package:vsdx/vsdx.dart';
import '../model/shape.dart';
export 'util.dart';
''', 'dart');
      expect(imps, containsAll(<String>[
        'dart:io',
        'package:vsdx/vsdx.dart',
        '../model/shape.dart',
        'util.dart',
      ]));
    });

    test('python import / from', () {
      final imps = extractImports('''
import os
import pkg.mod
from pkg.sub import thing
from . import sibling
from .rel import x
''', 'python');
      expect(imps, containsAll(<String>['os', 'pkg.mod', 'pkg.sub', '.', '.rel']));
    });

    test('js import/require/export-from', () {
      final imps = extractImports('''
import React from 'react';
import { a } from './a';
export { b } from './b';
const c = require('../c');
import './side-effect';
''', 'js');
      expect(imps, containsAll(<String>['react', './a', './b', '../c', './side-effect']));
    });
  });

  group('codeToSpec (temp project)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('code_import'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void write(String rel, String content) {
      final f = File('${tmp.path}/$rel');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    test('dart: intra-project edges only, package: resolves to lib/', () {
      write('lib/main.dart', "import 'package:app/util.dart';\nimport 'a/b.dart';\nimport 'dart:io';");
      write('lib/util.dart', "int x = 1;");
      write('lib/a/b.dart', "import '../util.dart';");
      final spec = codeToSpec(tmp.path, language: 'dart');
      expect(spec.nodes.map((n) => n.id), containsAll(<String>['lib/main', 'lib/util', 'lib/a/b']));
      bool edge(String a, String b) => spec.edges.any((e) => e.from == a && e.to == b);
      expect(edge('lib/main', 'lib/util'), isTrue); // package:app/util.dart
      expect(edge('lib/main', 'lib/a/b'), isTrue); // relative
      expect(edge('lib/a/b', 'lib/util'), isTrue); // ../util.dart
      // dart:io produced no edge (external).
      expect(spec.edges.every((e) => e.to != 'dart:io'), isTrue);
    });

    test('python: package __init__ and relative imports resolve', () {
      write('pkg/__init__.py', '');
      write('pkg/a.py', 'from . import b\nimport pkg.c');
      write('pkg/b.py', 'x = 1');
      write('pkg/c.py', 'y = 2');
      final spec = codeToSpec(tmp.path, language: 'python');
      bool edge(String a, String b) => spec.edges.any((e) => e.from == a && e.to == b);
      // `from . import b` → pkg/b ; `import pkg.c` → pkg/c
      expect(edge('pkg/a', 'pkg/b'), isTrue);
      expect(edge('pkg/a', 'pkg/c'), isTrue);
    });

    test('js: relative + index resolution, bare specifiers dropped', () {
      write('src/index.js', "import a from './a';\nimport dir from './dir';\nimport react from 'react';");
      write('src/a.js', 'export default 1;');
      write('src/dir/index.js', 'export default 2;');
      final spec = codeToSpec(tmp.path, language: 'js');
      bool edge(String a, String b) => spec.edges.any((e) => e.from == a && e.to == b);
      expect(edge('src/index', 'src/a'), isTrue);
      expect(edge('src/index', 'src/dir/index'), isTrue); // ./dir → dir/index
      expect(spec.edges.every((e) => !e.to.contains('react')), isTrue);
    });

    test('builds a valid round-trip .vsdx and auto-detects language', () {
      write('lib/main.dart', "import 'util.dart';");
      write('lib/util.dart', 'int x = 0;');
      final bytes = codeToSpec(tmp.path).build(); // language auto-detected = dart
      final doc = const DocumentParser().parse(bytes);
      expect(doc.pages.single.shapes.where((s) => !s.is1D), hasLength(2));
      expect(doc.pages.single.shapes.where((s) => s.is1D), hasLength(1));
      expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
    });
  });
}
