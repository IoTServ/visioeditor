/// Tiny ShapeSheet formula evaluator (M2-12 / M2-13 minimum viable subset).
///
/// We do **not** aim for a full Visio formula engine — Visio's evaluator
/// supports hundreds of functions and tight cycle detection. Instead, this
/// module:
///
///   * Parses numeric literals with optional Visio unit suffix
///     (e.g. `1.5 in`, `90 deg`, `25.4 mm`).
///   * Folds nested `MAX(...)`, `MIN(...)`, `IF(c,a,b)`, `ABS(...)`,
///     `ROUND(...)`, `NEG(...)`, `INT(...)`, `GUARD(...)`.
///   * Honours `+ - * / ( )` with the standard precedence.
///   * Optionally resolves bare cell names via [evaluateFormula]'s `locals`
///     map (`Width`, `Height`, `PinX`, …) for local ShapeSheet recalc.
///   * Optionally resolves `Sheet.n!Cell` via [sheetLookup] (page-level).
///   * Optionally peels `SETATREF` / `SETATREFEXPR` / `SETATREFEVAL` for
///     recalc transparency and input redirect ([computeSetAtRefRedirect]).
///   * Returns `null` when it encounters an unresolved external reference,
///     an `Inh`/`USE` directive, `THEMEVAL`, etc. The caller falls back to
///     the cell's `V=` literal (already pre-resolved by Visio).
///
/// The goal is to be **non-destructive**: if the evaluator can't make
/// sense of the expression it returns `null` so the cell's literal value
/// wins. We intentionally don't throw on parse errors.
library;

import 'package:meta/meta.dart';

import '../utils/units.dart';

/// Matches Visio cross-sheet cell refs: `Sheet.42!PinX`.
final RegExp sheetCellRefPattern = RegExp(
  r'Sheet\.(\d+)!([A-Za-z_][\w]*)',
  caseSensitive: false,
);

/// Every distinct sheet id referenced by `Sheet.n!…` in [raw].
Set<int> referencedSheetIds(String? raw) {
  if (raw == null || raw.isEmpty) return const <int>{};
  final out = <int>{};
  for (final m in sheetCellRefPattern.allMatches(raw)) {
    out.add(int.parse(m.group(1)!));
  }
  return out;
}

/// Rewrite `Sheet.n!Cell` refs in [raw] using [idMap] (old id → new id).
/// Unmapped sheet ids are left unchanged.
String rewriteSheetRefs(String raw, Map<int, int> idMap) {
  if (raw.isEmpty || idMap.isEmpty) return raw;
  return raw.replaceAllMapped(sheetCellRefPattern, (m) {
    final oldId = int.parse(m.group(1)!);
    final newId = idMap[oldId];
    if (newId == null) return m.group(0)!;
    return 'Sheet.$newId!${m.group(2)}';
  });
}

/// Whether [raw] references any sheet id in [ids].
bool formulaReferencesAnySheet(String? raw, Set<int> ids) {
  if (raw == null || raw.isEmpty || ids.isEmpty) return false;
  for (final m in sheetCellRefPattern.allMatches(raw)) {
    if (ids.contains(int.parse(m.group(1)!))) return true;
  }
  return false;
}

/// Parse a Visio `SETATREF(Controls.Name)` / `SETATREF(Controls.Name.X)`
/// target. Returns `null` when the formula is not a sole local Controls
/// SETATREF (no second arg / trailing arithmetic).
({String name, String? cell})? parseSetAtRefControl(String? raw) {
  final call = parseSetAtRefCall(raw);
  if (call == null || call.setExpression != null) return null;
  if (!isSoleSetAtRefFormula(raw)) return null;
  final m = RegExp(
    r'^Controls\.([A-Za-z_][\w]*)(?:\.([A-Za-z_][\w]*))?$',
    caseSensitive: false,
  ).firstMatch(call.reference.trim());
  if (m == null) return null;
  return (name: m.group(1)!, cell: m.group(2)?.toUpperCase());
}

/// Parsed `SETATREF(reference [, set_expression [, ignore_eval]])` call.
@immutable
class SetAtRefCall {
  const SetAtRefCall({
    required this.reference,
    this.setExpression,
    this.ignoreEval = false,
  });

  /// Target cell ref, e.g. `Controls.TextPosition.Y` / `User.DeltaX`.
  final String reference;

  /// Optional transform assigned to [reference] on input (may contain
  /// `SETATREFEXPR` / `SETATREFEVAL`).
  final String? setExpression;

  /// When true, SETATREF evaluates to 0 on recalc.
  final bool ignoreEval;
}

/// Result of redirecting an incoming UI/Automation value through SETATREF.
@immutable
class SetAtRefRedirect {
  const SetAtRefRedirect({required this.reference, required this.value});
  final String reference;
  final double value;
}

/// Locate the first `SETATREF(...)` call in [raw] (not EXPR/EVAL).
SetAtRefCall? parseSetAtRefCall(String? raw) {
  if (raw == null) return null;
  final src = raw.trim();
  if (src.isEmpty) return null;
  final m = RegExp(r'SETATREF(?!EXPR|EVAL)\s*\(', caseSensitive: false)
      .firstMatch(src);
  if (m == null) return null;
  final open = m.end - 1;
  final close = matchingCloseParen(src, open);
  if (close == null) return null;
  final parts = splitTopLevelArgs(src.substring(open + 1, close));
  if (parts.isEmpty || parts.first.trim().isEmpty) return null;
  return SetAtRefCall(
    reference: parts[0].trim(),
    setExpression: parts.length >= 2 ? parts[1].trim() : null,
    ignoreEval: parts.length >= 3 && isFormulaTruthy(parts[2]),
  );
}

/// Whether [raw] is exactly one `SETATREF(...)` call (no trailing ops).
bool isSoleSetAtRefFormula(String? raw) {
  if (raw == null) return false;
  final src = raw.trim();
  final m = RegExp(r'^SETATREF(?!EXPR|EVAL)\s*\(', caseSensitive: false)
      .firstMatch(src);
  if (m == null) return false;
  final open = m.end - 1;
  final close = matchingCloseParen(src, open);
  return close != null && close == src.length - 1;
}

/// Index of the `)` matching the `(` at [openIdx], or `null`.
int? matchingCloseParen(String s, int openIdx) {
  if (openIdx < 0 || openIdx >= s.length || s[openIdx] != '(') return null;
  var depth = 0;
  for (var i = openIdx; i < s.length; i++) {
    final c = s[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// Split function-argument text on top-level commas.
List<String> splitTopLevelArgs(String args) {
  if (args.isEmpty) return const <String>[''];
  final out = <String>[];
  var start = 0;
  var depth = 0;
  for (var i = 0; i < args.length; i++) {
    final c = args[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    } else if (c == ',' && depth == 0) {
      out.add(args.substring(start, i).trim());
      start = i + 1;
    }
  }
  out.add(args.substring(start).trim());
  return out;
}

bool isFormulaTruthy(String raw) {
  final t = raw.trim().toUpperCase();
  return t == 'TRUE' || t == '1' || t == '1.0';
}

bool _containsSetAtRefFn(String s) =>
    RegExp(r'SETATREF(?:EXPR|EVAL)?\s*\(', caseSensitive: false).hasMatch(s);

RegExp _setAtRefFnOpen(String name) {
  if (name.toUpperCase() == 'SETATREF') {
    return RegExp(r'SETATREF(?!EXPR|EVAL)\s*\(', caseSensitive: false);
  }
  return RegExp('$name\\s*\\(', caseSensitive: false);
}

/// Replace one leaf call of [name] whose args contain no nested SETATREF*.
/// Returns [src] unchanged when no leaf exists; `null` on malformed parens /
/// failed expand.
String? _expandOneLeafFn(
  String src,
  String name,
  String? Function(String args) expand,
) {
  final re = _setAtRefFnOpen(name);
  for (final m in re.allMatches(src)) {
    final open = m.end - 1;
    final close = matchingCloseParen(src, open);
    if (close == null) return null;
    final args = src.substring(open + 1, close);
    if (_containsSetAtRefFn(args)) continue;
    final rep = expand(args);
    if (rep == null) return null;
    return '${src.substring(0, m.start)}$rep${src.substring(close + 1)}';
  }
  return src;
}

/// Recalc peel: `SETATREFEXPR(x)`→x, `SETATREFEVAL(e)`→eval(e),
/// `SETATREF(ref[,…])`→lookup(ref) (or 0 when ignore_eval).
String? expandSetAtRefForRecalc(
  String src, {
  Map<String, double>? locals,
  double? Function(int sheetId, String cell)? sheetLookup,
  double? Function(String ref)? cellLookup,
}) {
  var s = src;
  for (var pass = 0; pass < 32; pass++) {
    final before = s;
    final expr = _expandOneLeafFn(s, 'SETATREFEXPR', (args) {
      if (args.trim().isEmpty) return '0';
      final v = evaluateFormula(
        args,
        locals: locals,
        sheetLookup: sheetLookup,
        cellLookup: cellLookup,
        expandSetAtRef: false,
      );
      if (v == null) return null;
      return _formulaNumberLiteral(v);
    });
    if (expr == null) return null;
    s = expr;

    final evaled = _expandOneLeafFn(s, 'SETATREFEVAL', (args) {
      final v = evaluateFormula(
        args,
        locals: locals,
        sheetLookup: sheetLookup,
        cellLookup: cellLookup,
        expandSetAtRef: false,
      );
      if (v == null) return null;
      return _formulaNumberLiteral(v);
    });
    if (evaled == null) return null;
    s = evaled;

    final refs = _expandOneLeafFn(s, 'SETATREF', (args) {
      final parts = splitTopLevelArgs(args);
      if (parts.isEmpty || parts.first.trim().isEmpty) return null;
      if (parts.length >= 3 && isFormulaTruthy(parts[2])) return '0';
      if (cellLookup == null) return null;
      final v = cellLookup(parts[0].trim());
      if (v == null) return null;
      return _formulaNumberLiteral(v);
    });
    if (refs == null) return null;
    s = refs;
    if (s == before) break;
  }
  return s;
}

/// Redirect an incoming UI value through a cell's SETATREF formula.
///
/// When [set_expression] is omitted, [incoming] is written to the reference.
/// When it contains `SETATREFEVAL(SETATREFEXPR(…)…)`, EXPR is replaced by
/// [incoming], EVAL is computed, and that result is written to the reference.
///
/// When [formulaOfRef] is provided, follows SETATREF chains (Visio allows up
/// to 10 hops): if the target cell's own `F=` is also SETATREF, the value is
/// redirected again until a non-SETATREF leaf is reached.
SetAtRefRedirect? computeSetAtRefRedirect(
  String? formula,
  double incoming, {
  Map<String, double>? locals,
  double? Function(int sheetId, String cell)? sheetLookup,
  double? Function(String ref)? cellLookup,
  String? Function(String ref)? formulaOfRef,
  int maxHops = 10,
}) {
  var currentFormula = formula;
  var currentIncoming = incoming;
  SetAtRefRedirect? last;
  final seen = <String>{};

  final hops = maxHops < 1 ? 1 : (maxHops > 10 ? 10 : maxHops);
  for (var hop = 0; hop < hops; hop++) {
    final one = _computeSetAtRefRedirectOnce(
      currentFormula,
      currentIncoming,
      locals: locals,
      sheetLookup: sheetLookup,
      cellLookup: cellLookup,
    );
    if (one == null) return last;
    last = one;
    final key = one.reference.toUpperCase();
    if (!seen.add(key)) return one; // cycle — stop at this write

    final nextF = formulaOfRef?.call(one.reference);
    if (nextF == null || parseSetAtRefCall(nextF) == null) {
      return one;
    }
    currentFormula = nextF;
    currentIncoming = one.value;
  }
  return last;
}

SetAtRefRedirect? _computeSetAtRefRedirectOnce(
  String? formula,
  double incoming, {
  Map<String, double>? locals,
  double? Function(int sheetId, String cell)? sheetLookup,
  double? Function(String ref)? cellLookup,
}) {
  final call = parseSetAtRefCall(formula);
  if (call == null) return null;
  final setExpr = call.setExpression;
  if (setExpr == null || setExpr.isEmpty) {
    return SetAtRefRedirect(reference: call.reference, value: incoming);
  }

  // Visio places the incoming value into SETATREFEXPR(…).
  var expr = setExpr;
  for (var i = 0; i < 16; i++) {
    final next = _expandOneLeafFn(
      expr,
      'SETATREFEXPR',
      (_) => _formulaNumberLiteral(incoming),
    );
    if (next == null) return null;
    if (next == expr) break;
    expr = next;
  }

  for (var i = 0; i < 16; i++) {
    final next = _expandOneLeafFn(expr, 'SETATREFEVAL', (args) {
      final v = evaluateFormula(
        args,
        locals: locals,
        sheetLookup: sheetLookup,
        cellLookup: cellLookup,
        expandSetAtRef: true,
      );
      if (v == null) return null;
      return _formulaNumberLiteral(v);
    });
    if (next == null) return null;
    if (next == expr) break;
    expr = next;
  }

  final v = evaluateFormula(
    expr,
    locals: locals,
    sheetLookup: sheetLookup,
    cellLookup: cellLookup,
  );
  if (v == null) return null;
  return SetAtRefRedirect(reference: call.reference, value: v);
}

/// Substitute `Sheet.n!Cell` with numeric literals via [sheetLookup].
/// Returns `null` if any referenced sheet/cell cannot be resolved.
String? substituteSheetRefs(
  String src,
  double? Function(int sheetId, String cell) sheetLookup,
) {
  final buf = StringBuffer();
  var last = 0;
  var saw = false;
  for (final m in sheetCellRefPattern.allMatches(src)) {
    saw = true;
    final id = int.parse(m.group(1)!);
    final cell = m.group(2)!;
    final v = sheetLookup(id, cell);
    if (v == null) return null;
    buf
      ..write(src.substring(last, m.start))
      ..write(_formulaNumberLiteral(v));
    last = m.end;
  }
  if (!saw) return src;
  buf.write(src.substring(last));
  return buf.toString();
}

String _formulaNumberLiteral(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return '${v.toInt()}';
  }
  // Trim trailing zeros so the lexer accepts a clean decimal.
  var s = v.toStringAsFixed(12);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Evaluate a ShapeSheet formula string. Returns the resolved value in
/// **inches** (for lengths) or the unitless number for ratios / angles
/// in degrees stay as-is — the caller decides what the unit is. When the
/// formula references anything we can't resolve (external sheet, Inh,
/// theme), returns `null`.
///
/// [locals] binds bare cell names (`Width`, `Height`, `PinX`, …) for local
/// ShapeSheet recalculation. Keys are matched case-insensitively.
///
/// [sheetLookup] resolves `Sheet.n!Cell` for page-level cross-shape
/// recalculation. Without it, any `!` reference hard-exits to `null`.
///
/// [cellLookup] resolves `Controls.*` / `User.*` / `Prop.*` (and similar)
/// for SETATREF recalc transparency. When SETATREF wrappers are present,
/// they are expanded via [expandSetAtRefForRecalc] first.
double? evaluateFormula(
  String? raw, {
  Map<String, double>? locals,
  double? Function(int sheetId, String cell)? sheetLookup,
  double? Function(String ref)? cellLookup,
  bool expandSetAtRef = true,
}) {
  if (raw == null) return null;
  var src = raw.trim();
  if (src.isEmpty) return null;
  if (sheetLookup != null && sheetCellRefPattern.hasMatch(src)) {
    final sub = substituteSheetRefs(src, sheetLookup);
    if (sub == null) return null;
    src = sub;
  }
  if (expandSetAtRef &&
      RegExp(r'SETATREF(?:EXPR|EVAL)?\s*\(', caseSensitive: false)
          .hasMatch(src)) {
    final expanded = expandSetAtRefForRecalc(
      src,
      locals: locals,
      sheetLookup: sheetLookup,
      cellLookup: cellLookup,
    );
    if (expanded == null) return null;
    src = expanded;
  }
  // Hard exits — these always need outer context to resolve.
  final upper = src.toUpperCase();
  if (upper.contains('THEMEVAL') ||
      upper.contains('THEMEGUARD') ||
      upper.contains('USE(') ||
      upper.contains('SETATREF') ||
      upper.startsWith('INH') ||
      upper.contains('!')) {
    return null;
  }
  try {
    // [_Parser] primes the lexer in its constructor. Keep construction inside
    // the same recovery boundary as parsing so an unsupported first token is
    // treated like every other unresolved Visio formula instead of escaping
    // into editor gesture handlers.
    final parser = _Parser(_Lexer(src), locals: locals);
    final v = parser.parseExpression();
    if (!parser.atEof) return null;
    return v;
  } catch (_) {
    return null;
  }
}

enum _Tok {
  number,
  unit,
  ident,
  plus,
  minus,
  star,
  slash,
  lparen,
  rparen,
  comma,
  eq,
  lt,
  gt,
  end,
}

class _Lexer {
  _Lexer(this._src);
  final String _src;
  int _pos = 0;
  _Tok _tok = _Tok.end;
  String _text = '';
  double _num = 0;

  _Tok get tok => _tok;
  String get text => _text;
  double get num => _num;

  void advance() {
    while (_pos < _src.length && _isWs(_src[_pos])) {
      _pos++;
    }
    if (_pos >= _src.length) {
      _tok = _Tok.end;
      return;
    }
    final c = _src[_pos];
    if (_isDigit(c) || (c == '.' && _pos + 1 < _src.length && _isDigit(_src[_pos + 1]))) {
      _readNumber();
      return;
    }
    if (_isAlpha(c)) {
      _readIdent();
      return;
    }
    _pos++;
    switch (c) {
      case '+':
        _tok = _Tok.plus;
      case '-':
        _tok = _Tok.minus;
      case '*':
        _tok = _Tok.star;
      case '/':
        _tok = _Tok.slash;
      case '(':
        _tok = _Tok.lparen;
      case ')':
        _tok = _Tok.rparen;
      case ',':
        _tok = _Tok.comma;
      case '=':
        _tok = _Tok.eq;
      case '<':
        _tok = _Tok.lt;
      case '>':
        _tok = _Tok.gt;
      default:
        throw const _FormulaError();
    }
  }

  void _readNumber() {
    final start = _pos;
    while (_pos < _src.length &&
        (_isDigit(_src[_pos]) || _src[_pos] == '.')) {
      _pos++;
    }
    if (_pos < _src.length && (_src[_pos] == 'e' || _src[_pos] == 'E')) {
      _pos++;
      if (_pos < _src.length && (_src[_pos] == '+' || _src[_pos] == '-')) {
        _pos++;
      }
      while (_pos < _src.length && _isDigit(_src[_pos])) {
        _pos++;
      }
    }
    final s = _src.substring(start, _pos);
    final v = double.tryParse(s);
    if (v == null) throw const _FormulaError();
    _num = v;
    _tok = _Tok.number;
  }

  void _readIdent() {
    final start = _pos;
    while (_pos < _src.length && _isIdent(_src[_pos])) {
      _pos++;
    }
    _text = _src.substring(start, _pos);
    final upper = _text.toUpperCase();
    if (_kLengthUnits.contains(upper) || _kAngleUnits.contains(upper)) {
      _tok = _Tok.unit;
    } else {
      _tok = _Tok.ident;
    }
  }

  static bool _isWs(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F;
  }

  static bool _isIdent(String c) {
    final code = c.codeUnitAt(0);
    return _isAlpha(c) || _isDigit(c) || code == 0x2E /* . */;
  }
}

class _Parser {
  _Parser(this._lex, {Map<String, double>? locals})
      : _locals = _normalizeLocals(locals) {
    _lex.advance();
  }
  final _Lexer _lex;
  final Map<String, double> _locals;

  static Map<String, double> _normalizeLocals(Map<String, double>? locals) {
    if (locals == null || locals.isEmpty) return const <String, double>{};
    return <String, double>{
      for (final e in locals.entries) e.key.toUpperCase(): e.value,
    };
  }

  bool get atEof => _lex.tok == _Tok.end;

  // expr := add (relop add)*
  double parseExpression() {
    var v = _add();
    while (_lex.tok == _Tok.eq || _lex.tok == _Tok.lt || _lex.tok == _Tok.gt) {
      final op = _lex.tok;
      _lex.advance();
      final r = _add();
      v = switch (op) {
        _Tok.eq => v == r ? 1 : 0,
        _Tok.lt => v < r ? 1 : 0,
        _Tok.gt => v > r ? 1 : 0,
        _ => v,
      } .toDouble();
    }
    return v;
  }

  double _add() {
    var v = _mul();
    while (_lex.tok == _Tok.plus || _lex.tok == _Tok.minus) {
      final op = _lex.tok;
      _lex.advance();
      final r = _mul();
      v = op == _Tok.plus ? v + r : v - r;
    }
    return v;
  }

  double _mul() {
    var v = _unary();
    while (_lex.tok == _Tok.star || _lex.tok == _Tok.slash) {
      final op = _lex.tok;
      _lex.advance();
      final r = _unary();
      v = op == _Tok.star ? v * r : (r == 0 ? 0 : v / r);
    }
    return v;
  }

  double _unary() {
    if (_lex.tok == _Tok.minus) {
      _lex.advance();
      return -_unary();
    }
    if (_lex.tok == _Tok.plus) {
      _lex.advance();
      return _unary();
    }
    return _primary();
  }

  double _primary() {
    if (_lex.tok == _Tok.number) {
      var n = _lex.num;
      _lex.advance();
      if (_lex.tok == _Tok.unit) {
        n = _applyUnit(n, _lex.text);
        _lex.advance();
      }
      return n;
    }
    if (_lex.tok == _Tok.lparen) {
      _lex.advance();
      final v = parseExpression();
      _expect(_Tok.rparen);
      return v;
    }
    if (_lex.tok == _Tok.ident) {
      final name = _lex.text.toUpperCase();
      _lex.advance();
      if (_lex.tok == _Tok.lparen) {
        return _callFunction(name);
      }
      final bound = _locals[name];
      if (bound != null) return bound;
      // Bare identifier — not resolvable here.
      throw const _FormulaError();
    }
    throw const _FormulaError();
  }

  double _callFunction(String name) {
    _expect(_Tok.lparen);
    final args = <double>[];
    if (_lex.tok != _Tok.rparen) {
      args.add(parseExpression());
      while (_lex.tok == _Tok.comma) {
        _lex.advance();
        args.add(parseExpression());
      }
    }
    _expect(_Tok.rparen);
    return _dispatch(name, args);
  }

  double _dispatch(String name, List<double> args) {
    switch (name) {
      case 'MAX':
        if (args.isEmpty) throw const _FormulaError();
        return args.reduce((a, b) => a > b ? a : b);
      case 'MIN':
        if (args.isEmpty) throw const _FormulaError();
        return args.reduce((a, b) => a < b ? a : b);
      case 'ABS':
        if (args.length != 1) throw const _FormulaError();
        return args[0].abs();
      case 'INT':
        if (args.length != 1) throw const _FormulaError();
        return args[0].truncateToDouble();
      case 'NEG':
        if (args.length != 1) throw const _FormulaError();
        return -args[0];
      case 'ROUND':
        if (args.length != 1 && args.length != 2) throw const _FormulaError();
        if (args.length == 1) return args[0].roundToDouble();
        final factor = _pow10(args[1].toInt());
        return (args[0] * factor).roundToDouble() / factor;
      case 'IF':
        if (args.length != 3) throw const _FormulaError();
        return args[0] != 0 ? args[1] : args[2];
      case 'AND':
        return args.every((a) => a != 0) ? 1 : 0;
      case 'OR':
        return args.any((a) => a != 0) ? 1 : 0;
      case 'NOT':
        if (args.length != 1) throw const _FormulaError();
        return args[0] == 0 ? 1 : 0;
      case 'PNT':
        // Visio's PNT(x,y) returns a "point" — for evaluation we collapse to x.
        if (args.isEmpty) throw const _FormulaError();
        return args[0];
      case 'SUM':
        return args.fold(0.0, (a, b) => a + b);
      case 'GUARD':
        // GUARD(value) just blocks Visio's re-evaluation; we ignore the
        // guard and return the inner value.
        if (args.length != 1) throw const _FormulaError();
        return args[0];
      default:
        throw const _FormulaError();
    }
  }

  void _expect(_Tok t) {
    if (_lex.tok != t) throw const _FormulaError();
    _lex.advance();
  }

  double _applyUnit(double n, String u) {
    final upper = u.toUpperCase();
    if (_kLengthUnits.contains(upper)) {
      final vsdxUnit = VsdxLengthUnit.tryParse(upper);
      return toInches(n, vsdxUnit);
    }
    if (_kAngleUnits.contains(upper)) {
      final vsdxUnit = VsdxAngleUnit.tryParse(upper);
      return toRadians(n, vsdxUnit);
    }
    return n;
  }

  static double _pow10(int n) {
    var v = 1.0;
    final abs = n.abs();
    for (var i = 0; i < abs; i++) {
      v *= 10;
    }
    return n < 0 ? 1 / v : v;
  }
}

class _FormulaError implements Exception {
  const _FormulaError();
}

const Set<String> _kLengthUnits = {
  'IN',
  'IN_F',
  'MM',
  'CM',
  'M',
  'PT',
  'PICA',
  'FT',
  'DT',
};

const Set<String> _kAngleUnits = {
  'DEG',
  'RAD',
};
