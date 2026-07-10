/// Tiny ShapeSheet formula evaluator (M2-12 / M2-13 minimum viable subset).
///
/// We do **not** aim for a full Visio formula engine — Visio's evaluator
/// supports hundreds of functions and tight cycle detection. Instead, this
/// module:
///
///   * Parses numeric literals with optional Visio unit suffix
///     (e.g. `1.5 in`, `90 deg`, `25.4 mm`).
///   * Folds nested `MAX(...)`, `MIN(...)`, `IF(c,a,b)`, `ABS(...)`,
///     `ROUND(...)`, `NEG(...)`, `INT(...)`.
///   * Honours `+ - * / ( )` with the standard precedence.
///   * Returns `null` when it encounters an *external* reference
///     (`Sheet.42!PinX`), an `Inh`/`USE` directive, `THEMEVAL`, etc. The
///     caller falls back to the cell's `V=` literal (already pre-resolved
///     by Visio).
///
/// The goal is to be **non-destructive**: if the evaluator can't make
/// sense of the expression it returns `null` so the cell's literal value
/// wins. We intentionally don't throw on parse errors.
library;

import '../utils/units.dart';

/// Evaluate a ShapeSheet formula string. Returns the resolved value in
/// **inches** (for lengths) or the unitless number for ratios / angles
/// in degrees stay as-is — the caller decides what the unit is. When the
/// formula references anything we can't resolve (external sheet, Inh,
/// theme), returns `null`.
double? evaluateFormula(String? raw) {
  if (raw == null) return null;
  final src = raw.trim();
  if (src.isEmpty) return null;
  // Hard exits — these always need outer context to resolve.
  final upper = src.toUpperCase();
  if (upper.contains('THEMEVAL') ||
      upper.contains('THEMEGUARD') ||
      upper.contains('USE(') ||
      upper.startsWith('INH') ||
      upper.contains('!')) {
    return null;
  }
  final lex = _Lexer(src);
  final parser = _Parser(lex);
  try {
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
  _Parser(this._lex) {
    _lex.advance();
  }
  final _Lexer _lex;

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
