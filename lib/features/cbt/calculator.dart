import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/ui.dart';

/// ============================================================
/// THE EXAM CALCULATOR
///
/// A button-only scientific calculator that opens over a sitting. There
/// is no text field: the student cannot type an expression, cannot paste
/// one in, and cannot smuggle anything past the parser, because the only
/// tokens that exist are the ones on these keys.
///
/// Nothing here evaluates code. The engine below is a hand-written
/// tokenizer, a shunting-yard pass and an RPN walk over a fixed set of
/// operators and functions. Anything it cannot parse comes back as null
/// and the screen says "Check that expression" — quietly, with no error
/// code and no crash.
/// ============================================================

/// ANS survives between evaluations and between openings of the sheet, so
/// a student can carry a result from one step of a calculation to the next.
double _lastAnswer = 0;

Future<void> showBxCalculator(BuildContext context) {
  final c = context.bx;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface,
    barrierColor: c.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BxRadius.sheet),
    builder: (_) => const _CalculatorSheet(),
  );
}

// ============================================================
// THE ENGINE — tokenizer → shunting-yard → RPN evaluator
// ============================================================

enum _TokKind { number, op, func, lparen, rparen }

@immutable
class _Tok {
  final _TokKind kind;
  final String text;
  final double value;
  const _Tok(this.kind, this.text, [this.value = 0]);
}

abstract final class _Calc {
  static const _funcWords = ['sin', 'cos', 'tan', 'log', 'ln'];

  /// Binary and unary precedence. Functions sit above all of them.
  static const _prec = <String, int>{
    '+': 1,
    '−': 1,
    '×': 2,
    '÷': 2,
    'u−': 3,
    '^': 4,
  };

  /// Returns null for anything that does not parse or does not evaluate
  /// to a finite number. Callers show one calm message; they never see
  /// an exception.
  static double? evaluate(String input, {required bool degrees}) {
    final tokens = _tokenize(input);
    if (tokens == null || tokens.isEmpty) return null;
    final rpn = _toRpn(tokens);
    if (rpn == null) return null;
    return _run(rpn, degrees);
  }

  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static List<_Tok>? _tokenize(String src) {
    final out = <_Tok>[];

    // 2π, 3(4+1) and 2sin(1) all mean a multiplication the student did
    // not have to press.
    void value(_Tok t) {
      if (out.isNotEmpty &&
          (out.last.kind == _TokKind.number ||
              out.last.kind == _TokKind.rparen)) {
        out.add(const _Tok(_TokKind.op, '×'));
      }
      out.add(t);
    }

    var i = 0;
    while (i < src.length) {
      final ch = src[i];
      if (ch == ' ') {
        i++;
        continue;
      }
      if (_isDigit(ch) || ch == '.') {
        final start = i;
        var dots = 0;
        while (i < src.length && (_isDigit(src[i]) || src[i] == '.')) {
          if (src[i] == '.') dots++;
          i++;
        }
        if (dots > 1) return null;
        final raw = src.substring(start, i);
        final n = double.tryParse(raw);
        if (n == null) return null;
        value(_Tok(_TokKind.number, raw, n));
        continue;
      }
      if (ch == 'π') {
        value(const _Tok(_TokKind.number, 'π', math.pi));
        i++;
        continue;
      }
      if (src.startsWith('ANS', i)) {
        value(_Tok(_TokKind.number, 'ANS', _lastAnswer));
        i += 3;
        continue;
      }
      if (ch == '√') {
        value(const _Tok(_TokKind.func, '√'));
        i++;
        continue;
      }
      final word = _funcWords.where((w) => src.startsWith(w, i)).firstOrNull;
      if (word != null) {
        value(_Tok(_TokKind.func, word));
        i += word.length;
        continue;
      }
      if (ch == '(') {
        value(const _Tok(_TokKind.lparen, '('));
        i++;
        continue;
      }
      if (ch == ')') {
        out.add(const _Tok(_TokKind.rparen, ')'));
        i++;
        continue;
      }
      final op = switch (ch) {
        '+' => '+',
        '-' || '−' => '−',
        '*' || '×' => '×',
        '/' || '÷' => '÷',
        '^' => '^',
        _ => null,
      };
      if (op == null) return null;
      out.add(_Tok(_TokKind.op, op));
      i++;
    }
    return out;
  }

  static List<_Tok>? _toRpn(List<_Tok> tokens) {
    final out = <_Tok>[];
    final ops = <_Tok>[];
    _Tok? prev;

    for (final t in tokens) {
      if (t.kind == _TokKind.number) {
        out.add(t);
        prev = t;
        continue;
      }
      if (t.kind == _TokKind.func || t.kind == _TokKind.lparen) {
        ops.add(t);
        prev = t;
        continue;
      }
      if (t.kind == _TokKind.rparen) {
        var closed = false;
        while (ops.isNotEmpty) {
          final top = ops.removeLast();
          if (top.kind == _TokKind.lparen) {
            closed = true;
            break;
          }
          out.add(top);
        }
        if (!closed) return null;
        prev = t;
        continue;
      }

      // An operator. At the start of a value only a sign makes sense.
      final atValueStart = prev == null ||
          prev.kind == _TokKind.op ||
          prev.kind == _TokKind.lparen ||
          prev.kind == _TokKind.func;
      var op = t;
      if (atValueStart) {
        if (t.text == '+') {
          prev = t;
          continue;
        }
        if (t.text != '−') return null;
        op = const _Tok(_TokKind.op, 'u−');
      }

      final p = _prec[op.text]!;
      final rightAssoc = op.text == '^';
      // A sign is a prefix operator: it has no left operand, so it never
      // pops anything — that is what keeps 2^−3 parsing.
      while (op.text != 'u−' &&
          ops.isNotEmpty &&
          ops.last.kind != _TokKind.lparen) {
        final top = ops.last;
        final tp = top.kind == _TokKind.func ? 5 : _prec[top.text]!;
        if (tp > p || (tp == p && !rightAssoc)) {
          out.add(ops.removeLast());
        } else {
          break;
        }
      }
      ops.add(op);
      prev = t;
    }

    while (ops.isNotEmpty) {
      final top = ops.removeLast();
      if (top.kind == _TokKind.lparen) return null; // an unclosed bracket
      out.add(top);
    }
    return out;
  }

  static double? _run(List<_Tok> rpn, bool degrees) {
    final stack = <double>[];
    for (final t in rpn) {
      if (t.kind == _TokKind.number) {
        stack.add(t.value);
        continue;
      }
      if (t.kind == _TokKind.func || t.text == 'u−') {
        if (stack.isEmpty) return null;
        final r = _unary(t.text, stack.removeLast(), degrees);
        if (r == null) return null;
        stack.add(r);
        continue;
      }
      if (stack.length < 2) return null;
      final b = stack.removeLast();
      final a = stack.removeLast();
      final r = _binary(t.text, a, b);
      if (r == null) return null;
      stack.add(r);
    }
    if (stack.length != 1) return null;
    final v = stack.single;
    if (!v.isFinite) return null;
    return v.abs() < 1e-12 ? 0 : v; // sin(180°) is zero, not 1.2e-16
  }

  static double? _unary(String f, double x, bool degrees) {
    final a = degrees ? x * math.pi / 180 : x;
    switch (f) {
      case 'u−':
        return -x;
      case 'sin':
        return math.sin(a);
      case 'cos':
        return math.cos(a);
      case 'tan':
        final cosine = math.cos(a);
        if (cosine.abs() < 1e-12) return null; // 90° has no tangent
        return math.sin(a) / cosine;
      case 'log':
        return x > 0 ? math.log(x) / math.ln10 : null;
      case 'ln':
        return x > 0 ? math.log(x) : null;
      case '√':
        return x >= 0 ? math.sqrt(x) : null;
    }
    return null;
  }

  static double? _binary(String op, double a, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? null : a / b;
      case '^':
        final r = math.pow(a, b);
        return r is double && r.isFinite ? r : null;
    }
    return null;
  }

  /// Twelve significant figures, then every trailing zero trimmed, so
  /// 0.1 + 0.2 reads as 0.3 and not as the float underneath it.
  static String format(double v) {
    if (v == 0) return '0';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
    var s = v.toStringAsPrecision(12);
    if (s.contains('e')) {
      final parts = s.split('e');
      return '${_trim(parts.first)}e${parts.last}';
    }
    return _trim(s);
  }

  static String _trim(String s) {
    if (!s.contains('.')) return s;
    var out = s.replaceFirst(RegExp(r'0+$'), '');
    if (out.endsWith('.')) out = out.substring(0, out.length - 1);
    return out;
  }
}

// ============================================================
// THE SHEET
// ============================================================

class _CalculatorSheet extends StatefulWidget {
  const _CalculatorSheet();

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  String _expr = '';
  String _result = '';
  bool _degrees = true;
  bool _bad = false;
  bool _settled = false; // the last thing pressed was '='

  static const _tail = ['ANS', 'sin', 'cos', 'tan', 'log', 'ln'];

  void _press(String token, {required bool startsValue}) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_settled) {
        // After a result, a digit starts fresh while an operator carries
        // the answer forward — the way a real calculator behaves.
        _expr = startsValue ? '' : 'ANS';
        if (startsValue) _result = '';
        _settled = false;
      }
      _bad = false;
      _expr += token;
    });
  }

  void _backspace() {
    if (_expr.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      final word = _tail.where(_expr.endsWith).firstOrNull;
      _expr = _expr.substring(0, _expr.length - (word?.length ?? 1));
      _bad = false;
      _settled = false;
    });
  }

  void _clear() {
    HapticFeedback.selectionClick();
    setState(() {
      _expr = '';
      _result = '';
      _bad = false;
      _settled = false;
    });
  }

  void _equals() {
    if (_expr.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final v = _Calc.evaluate(_expr, degrees: _degrees);
    setState(() {
      if (v == null) {
        _bad = true;
        return;
      }
      _lastAnswer = v;
      _result = _Calc.format(v);
      _bad = false;
      _settled = true;
    });
  }

  void _setDegrees(bool degrees) {
    setState(() {
      _degrees = degrees;
      // A result already on screen is re-read in the new mode rather than
      // left there quietly wrong.
      if (_result.isNotEmpty && !_bad) {
        final v = _Calc.evaluate(_expr, degrees: degrees);
        if (v == null) {
          _bad = true;
        } else {
          _lastAnswer = v;
          _result = _Calc.format(v);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final ans = _Calc.format(_lastAnswer);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              BxSpace.md, BxSpace.xs, BxSpace.md, BxSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.lineStrong,
                    borderRadius: BorderRadius.circular(BxRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: BxSpace.sm),
              Row(
                children: [
                  const Expanded(child: BxEyebrow('Calculator')),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, size: 19, color: c.muted),
                  ),
                ],
              ),
              const SizedBox(height: BxSpace.xs),
              _display(c, ans),
              const SizedBox(height: BxSpace.sm),
              Row(
                children: [
                  SizedBox(
                    width: 152,
                    child: BxSegmented<bool>(
                      value: _degrees,
                      options: const [
                        BxOption(true, 'DEG'),
                        BxOption(false, 'RAD'),
                      ],
                      onChanged: _setDegrees,
                    ),
                  ),
                  const Spacer(),
                  BxChip(
                    'ANS ${ans.length > 12 ? '${ans.substring(0, 12)}…' : ans}',
                    dense: true,
                    icon: Icons.history_rounded,
                  ),
                ],
              ),
              const SizedBox(height: BxSpace.sm),
              ..._keypad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _display(BxColors c, String ans) {
    return BxCard(
      fill: c.surfaceSunken,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 22,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Text(
                _expr.isEmpty ? '0' : _expr,
                style: BxType.mono(c.muted, size: 15),
              ),
            ),
          ),
          const SizedBox(height: BxSpace.xs),
          SizedBox(
            height: 38,
            child: Align(
              alignment: Alignment.centerRight,
              child: _bad
                  ? Text('Check that expression',
                      style: BxType.bodyStrong(c.danger))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(_result.isEmpty ? '0' : _result,
                          style: BxType.figure(c.ink)),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _keypad() {
    Widget row(List<Widget> keys) => Padding(
          padding: const EdgeInsets.only(bottom: BxSpace.xs),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                for (var i = 0; i < keys.length; i++) ...[
                  if (i > 0) const SizedBox(width: BxSpace.xs),
                  Expanded(child: keys[i]),
                ],
              ],
            ),
          ),
        );

    Widget digit(String d) =>
        _CalcKey(label: d, onTap: () => _press(d, startsValue: true));

    Widget op(String o) => _CalcKey(
          label: o,
          role: _KeyRole.op,
          onTap: () => _press(o, startsValue: false),
        );

    Widget fn(String label, String token) => _CalcKey(
          label: label,
          role: _KeyRole.func,
          onTap: () => _press(token, startsValue: true),
        );

    return [
      row([
        _CalcKey(label: 'AC', role: _KeyRole.clear, onTap: _clear),
        fn('(', '('),
        _CalcKey(
          label: ')',
          role: _KeyRole.func,
          onTap: () => _press(')', startsValue: false),
        ),
        _CalcKey(
          label: '⌫',
          role: _KeyRole.func,
          icon: Icons.backspace_outlined,
          onTap: _backspace,
        ),
      ]),
      row([fn('sin', 'sin('), fn('cos', 'cos('), fn('tan', 'tan('), op('^')]),
      row([fn('log', 'log('), fn('ln', 'ln('), fn('π', 'π'), fn('√', '√(')]),
      row([digit('7'), digit('8'), digit('9'), op('÷')]),
      row([digit('4'), digit('5'), digit('6'), op('×')]),
      row([digit('1'), digit('2'), digit('3'), op('−')]),
      row([
        digit('0'),
        digit('.'),
        _CalcKey(
          label: 'ANS',
          role: _KeyRole.func,
          onTap: () => _press('ANS', startsValue: true),
        ),
        op('+'),
      ]),
      BxButton(
        '=',
        large: true,
        expand: true,
        onPressed: _equals,
      ),
    ];
  }
}

enum _KeyRole { digit, op, func, clear }

class _CalcKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final _KeyRole role;
  final IconData? icon;

  const _CalcKey({
    required this.label,
    required this.onTap,
    this.role = _KeyRole.digit,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final (Color fill, Color ink, Color border) = switch (role) {
      _KeyRole.digit => (c.surface, c.ink, c.line),
      _KeyRole.op => (c.surfaceAlt, c.goldDeep, c.gold.withValues(alpha: 0.42)),
      _KeyRole.func => (c.surfaceSunken, c.inkSoft, c.line),
      _KeyRole.clear => (c.dangerTint, c.danger, c.danger.withValues(alpha: 0.36)),
    };

    return BxScaleTap(
      onTap: onTap,
      scale: 0.94,
      borderRadius: BorderRadius.circular(BxRadius.sm),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(color: border),
        ),
        child: icon != null
            ? Icon(icon, size: 19, color: ink)
            : Text(
                label,
                style: BxType.mono(ink,
                    size: label.length > 1 ? 13.5 : 17, weight: 600),
              ),
      ),
    );
  }
}
