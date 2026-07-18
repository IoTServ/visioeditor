/// SQL DDL (`CREATE TABLE …`) → [DiagramSpec] ER diagram (→ `.vsdx`).
///
/// Parses a pragmatic subset: table names, columns with types, PRIMARY KEY
/// (inline or table-level), and FOREIGN KEY … REFERENCES (inline or
/// table-level, incl. `CONSTRAINT …`). Each table becomes a box whose label is
/// the table name plus its columns (PK / FK marked); every foreign key becomes
/// an edge to the referenced table.
///
/// Handles most hand-written / dumped DDL across dialects; exotic syntax is
/// skipped, not fatal. See `docs/MCP_SKILL_PLAN.md` (M5).
library;

import 'dart:math' as math;

import 'diagram_spec.dart';

/// Parse SQL [ddl] into an ER [DiagramSpec].
DiagramSpec sqlToSpec(String ddl) {
  final sql = _stripComments(ddl);
  final nodes = <NodeSpec>[];
  final edges = <EdgeSpec>[];
  final tableIds = <String, String>{}; // lower-case name -> node id

  for (final table in _tables(sql)) {
    final id = table.name;
    tableIds[table.name.toLowerCase()] = id;
  }

  for (final table in _tables(sql)) {
    final lines = <String>[table.name, '─────────────'];
    var maxLen = table.name.length;
    for (final col in table.columns) {
      final marks = <String>[
        if (col.pk) 'PK',
        if (col.fk) 'FK',
      ];
      final suffix = marks.isEmpty ? '' : ' (${marks.join(', ')})';
      final line = '${col.name}$suffix';
      lines.add(line);
      maxLen = math.max(maxLen, line.length);
    }
    final w = math.max(1.8, 0.10 * maxLen + 0.4);
    final h = math.max(0.9, 0.26 * lines.length + 0.2);
    nodes.add(NodeSpec(
      id: table.name,
      stencil: 'process',
      text: lines.join('\n'),
      w: w,
      h: h,
      fill: '#DAE8FC',
      line: '#6C8EBF',
    ));

    for (final fk in table.foreignKeys) {
      final target = tableIds[fk.refTable.toLowerCase()];
      if (target == null) continue;
      edges.add(EdgeSpec(
          from: table.name, to: target, label: fk.column, arrow: true));
    }
  }

  return DiagramSpec(
    title: 'ER Diagram',
    direction: 'LR',
    spacing: 0.9,
    nodes: nodes,
    edges: edges,
  );
}

/// Build `.vsdx` bytes directly from SQL DDL.
List<int> sqlToVsdx(String ddl) => sqlToSpec(ddl).build();

// --- parsing ---------------------------------------------------------------

class _Table {
  _Table(this.name);
  final String name;
  final List<_Column> columns = <_Column>[];
  final List<_Fk> foreignKeys = <_Fk>[];
}

class _Column {
  _Column(this.name, {this.pk = false, this.fk = false});
  final String name;
  bool pk;
  bool fk;
}

class _Fk {
  _Fk(this.column, this.refTable, this.refColumn);
  final String column;
  final String refTable;
  final String refColumn;
}

String _unquote(String s) =>
    s.replaceAll(RegExp('[`"\\[\\]]'), '').trim();

String _stripComments(String sql) => sql
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .replaceAll(RegExp(r'--[^\n]*'), ' ');

final _createRe = RegExp(
  r'create\s+table\s+(?:if\s+not\s+exists\s+)?(.+?)\s*\(',
  caseSensitive: false,
);

Iterable<_Table> _tables(String sql) sync* {
  for (final m in _createRe.allMatches(sql)) {
    final rawName = _unquote(m.group(1)!);
    final name = rawName.contains('.') ? rawName.split('.').last : rawName;
    final open = m.end - 1; // position of '('
    final close = _matchParen(sql, open);
    if (close < 0) continue;
    final body = sql.substring(open + 1, close);
    yield _parseTable(name, body);
  }
}

int _matchParen(String s, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < s.length; i++) {
    final c = s[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

_Table _parseTable(String name, String body) {
  final table = _Table(name);
  final byName = <String, _Column>{};
  for (final item in _splitTopLevel(body)) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    final lower = trimmed.toLowerCase();
    final isConstraintClause = lower.startsWith('primary key') ||
        lower.startsWith('foreign key') ||
        lower.startsWith('unique') ||
        lower.startsWith('key ') ||
        lower.startsWith('index') ||
        lower.startsWith('check') ||
        lower.startsWith('constraint');

    if (isConstraintClause) {
      // Table-level FOREIGN KEY (col) REFERENCES tbl(col).
      if (lower.contains('foreign key')) {
        final fk = _fkRe.firstMatch(trimmed);
        if (fk != null) {
          final col = _unquote(fk.group(1)!);
          table.foreignKeys.add(
              _Fk(col, _unquote(fk.group(2)!), _unquote(fk.group(3)!)));
          byName[col.toLowerCase()]?.fk = true;
        }
      }
      // Table-level PRIMARY KEY (a, b).
      if (lower.contains('primary key')) {
        for (final c in _parenCols(trimmed)) {
          byName[c.toLowerCase()]?.pk = true;
        }
      }
      continue; // all other constraints are not modelled
    }

    // A column definition: first token is the name.
    final colName = _unquote(trimmed.split(RegExp(r'\s')).first);
    if (colName.isEmpty) continue;
    final col = _Column(colName,
        pk: lower.contains('primary key'),
        fk: lower.contains('references'));
    table.columns.add(col);
    byName[colName.toLowerCase()] = col;

    // Inline REFERENCES tbl(col)
    final inlineFk = _inlineFkRe.firstMatch(trimmed);
    if (inlineFk != null) {
      table.foreignKeys.add(_Fk(
        colName,
        _unquote(inlineFk.group(1)!),
        _unquote(inlineFk.group(2)!),
      ));
      col.fk = true;
    }
  }
  return table;
}

final _fkRe = RegExp(
  r'foreign\s+key\s*\(\s*([`"\[]?\w+[`"\]]?)\s*\)\s*references\s+([`"\[]?[\w.]+[`"\]]?)\s*\(\s*([`"\[]?\w+[`"\]]?)\s*\)',
  caseSensitive: false,
);

final _inlineFkRe = RegExp(
  r'references\s+([`"\[]?[\w.]+[`"\]]?)\s*\(\s*([`"\[]?\w+[`"\]]?)\s*\)',
  caseSensitive: false,
);

List<String> _parenCols(String s) {
  final m = RegExp(r'\(([^)]*)\)').firstMatch(s);
  if (m == null) return const <String>[];
  return <String>[
    for (final c in m.group(1)!.split(',')) _unquote(c),
  ];
}

/// Split a table body on top-level commas (ignoring commas inside parens).
Iterable<String> _splitTopLevel(String body) sync* {
  var depth = 0;
  final buf = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == ',' && depth == 0) {
      yield buf.toString();
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  if (buf.isNotEmpty) yield buf.toString();
}
