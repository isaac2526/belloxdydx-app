import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// CGPA CALCULATOR
///
/// Deliberately public: a student who has not paid a kobo can still
/// work out their GPA and print a clean sheet from it. It is the
/// friendliest possible front door, and it is honest — nothing on this
/// screen is teased and then locked.
/// ============================================================

enum _Scale { five, four }

const _grades5 = <String, int>{'A': 5, 'B': 4, 'C': 3, 'D': 2, 'E': 1, 'F': 0};
const _grades4 = <String, int>{'A': 4, 'B': 3, 'C': 2, 'D': 1, 'F': 0};

/// The Nigerian degree classifications, with the thresholds that apply
/// on each scale.
({String name, BxAccent accent}) _classify(double gpa, _Scale scale) {
  final t = scale == _Scale.five
      ? const [4.50, 3.50, 2.40, 1.50, 1.00]
      : const [3.50, 3.00, 2.00, 1.50, 1.00];
  if (gpa >= t[0]) return (name: 'First Class', accent: BxAccent.success);
  if (gpa >= t[1]) return (name: 'Second Class Upper', accent: BxAccent.gold);
  if (gpa >= t[2]) return (name: 'Second Class Lower', accent: BxAccent.info);
  if (gpa >= t[3]) return (name: 'Third Class', accent: BxAccent.violet);
  if (gpa >= t[4]) return (name: 'Pass', accent: BxAccent.warning);
  return (name: 'Fail', accent: BxAccent.danger);
}

class _CourseRow {
  _CourseRow({this.units = 3});

  final TextEditingController name = TextEditingController();
  int units;
  String? grade;

  void dispose() => name.dispose();
}

class CgpaScreen extends ConsumerStatefulWidget {
  const CgpaScreen({super.key});

  @override
  ConsumerState<CgpaScreen> createState() => _CgpaScreenState();
}

class _CgpaScreenState extends ConsumerState<CgpaScreen> {
  final _rows = <_CourseRow>[
    _CourseRow(),
    _CourseRow(),
    _CourseRow(units: 2),
    _CourseRow(),
  ];

  final _studentName = TextEditingController();
  final _prevCgpaCtl = TextEditingController();
  final _prevUnitsCtl = TextEditingController();

  _Scale _scale = _Scale.five;
  bool _hasPrevious = false;
  bool _exporting = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _studentName.dispose();
    _prevCgpaCtl.dispose();
    _prevUnitsCtl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------- maths

  Map<String, int> get _table => _scale == _Scale.five ? _grades5 : _grades4;
  double get _max => _scale == _Scale.five ? 5.0 : 4.0;

  Iterable<_CourseRow> get _graded => _rows.where((r) => r.grade != null);

  int get _totalUnits => _graded.fold(0, (s, r) => s + r.units);

  int get _totalPoints =>
      _graded.fold(0, (s, r) => s + r.units * (_table[r.grade] ?? 0));

  /// This semester only. Null until at least one grade is picked.
  double? get _gpa => _totalUnits == 0 ? null : _totalPoints / _totalUnits;

  double? get _prevGpa {
    if (!_hasPrevious) return null;
    final v = double.tryParse(_prevCgpaCtl.text.trim());
    if (v == null || v < 0 || v > _max) return null;
    return v;
  }

  int? get _prevUnits {
    if (!_hasPrevious) return null;
    final v = int.tryParse(_prevUnitsCtl.text.trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  bool get _carriesPrevious => _prevGpa != null && _prevUnits != null;

  /// The figure on the card: cumulative when a previous CGPA is carried
  /// in, otherwise the semester GPA.
  double? get _figure {
    final gpa = _gpa;
    if (gpa == null) return null;
    final pg = _prevGpa;
    final pu = _prevUnits;
    if (pg == null || pu == null) return gpa;
    return (pg * pu + _totalPoints) / (pu + _totalUnits);
  }

  int get _figureUnits => _carriesPrevious ? _totalUnits + _prevUnits! : _totalUnits;

  double get _figurePoints => _carriesPrevious
      ? _totalPoints + (_prevGpa! * _prevUnits!)
      : _totalPoints.toDouble();

  // ---------------------------------------------------------- actions

  void _setScale(_Scale s) {
    setState(() {
      _scale = s;
      // 'E' only exists on the 5.0 scale; drop it rather than pretend.
      for (final r in _rows) {
        if (r.grade != null && !_table.containsKey(r.grade)) r.grade = null;
      }
    });
  }

  void _addRow() => setState(() => _rows.add(_CourseRow()));

  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() => _rows.removeAt(i).dispose());
  }

  String _studentLabel() {
    final profile = ref.read(sessionProvider).profile;
    if (profile != null && profile.fullName.isNotEmpty) return profile.fullName;
    final typed = _studentName.text.trim();
    return typed.isEmpty ? 'Student' : typed;
  }

  Future<void> _export() async {
    final figure = _figure;
    if (figure == null) {
      bxToast(context, 'Pick a grade for at least one course first.',
          error: true);
      return;
    }
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final bytes = await _buildSheet(figure);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Belloxdydx CGPA sheet',
      );
    } catch (_) {
      if (mounted) {
        bxToast(
          context,
          'The result sheet did not open on this phone. Your figures are '
          'still here — try again in a moment.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// A plain, printable sheet. Kept to the built-in font's character set
  /// so it renders the same on every phone and printer.
  Future<Uint8List> _buildSheet(double figure) async {
    final cls = _classify(figure, _scale);
    final scaleLabel = _scale == _Scale.five ? '5.0' : '4.0';
    final date = DateFormat('d MMMM yyyy').format(DateTime.now());

    final data = <List<String>>[];
    var n = 0;
    for (final r in _rows) {
      final g = r.grade;
      if (g == null) continue;
      n++;
      final title = r.name.text.trim();
      data.add([
        '$n',
        title.isEmpty ? 'Course $n' : title,
        '${r.units}',
        g,
        '${r.units * (_table[g] ?? 0)}',
      ]);
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BELLOXDYDX',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      letterSpacing: 3,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'CGPA result sheet',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Text(
                date,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            _studentLabel(),
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Computed on the $scaleLabel scale',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: const ['#', 'Course', 'Units', 'Grade', 'Points'],
            data: data,
            headerStyle: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 18),
          if (_carriesPrevious)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                'Carried forward: CGPA ${_prevGpa!.toStringAsFixed(2)} over '
                '${_prevUnits!} units. This semester: '
                '${_gpa!.toStringAsFixed(2)} over $_totalUnits units.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _carriesPrevious ? 'CUMULATIVE CGPA' : 'GPA',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        letterSpacing: 2,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${figure.toStringAsFixed(2)} / $scaleLabel',
                      style: pw.TextStyle(
                        fontSize: 26,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(cls.name, style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Total units: $_figureUnits',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Total points: ${_figurePoints.toStringAsFixed(1)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 26),
          pw.Text(
            'Worked out on the free Belloxdydx CGPA calculator. '
            '${BxConfig.siteUrl}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(sessionProvider).profile;

    return Scaffold(
      appBar: BxAppBar(
        title: 'CGPA Calculator',
        subtitle: 'Free · no account needed',
        actions: [
          if (profile == null)
            BxButton.ghost(
              'Sign in',
              onPressed: () => context.go(Routes.welcome),
            ),
        ],
      ),
      body: BxPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _result(),
            const SizedBox(height: BxSpace.lg),
            _scaleCard(),
            if (profile == null) ...[
              const SizedBox(height: BxSpace.md),
              BxCard(
                padding: const EdgeInsets.all(BxSpace.md),
                child: BxField(
                  label: 'Your name',
                  controller: _studentName,
                  hint: 'Goes on the printed sheet',
                  capitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
            const SizedBox(height: BxSpace.xl),
            BxSectionHeader(
              title: 'Your courses',
              eyebrow: 'This semester',
              subtitle:
                  'Units and grade for each one. Leave a grade empty and that '
                  'course sits out.',
              trailing: BxChip(
                '$_totalUnits units',
                accent: BxAccent.gold,
                icon: Icons.functions_rounded,
              ),
            ),
            for (var i = 0; i < _rows.length; i++) ...[
              _courseCard(i),
              const SizedBox(height: BxSpace.xs),
            ],
            const SizedBox(height: BxSpace.xs),
            BxButton.secondary(
              'Add course',
              icon: Icons.add_rounded,
              expand: true,
              onPressed: _addRow,
            ),
            const SizedBox(height: BxSpace.xl),
            _previousCard(),
            const SizedBox(height: BxSpace.xl),
            BxButton(
              'Export result sheet',
              icon: Icons.print_outlined,
              expand: true,
              large: true,
              loading: _exporting,
              loadingLabel: 'Building your sheet…',
              onPressed: _figure == null ? null : _export,
            ),
            const SizedBox(height: BxSpace.sm),
            Text(
              'Nothing on this screen leaves your phone. Print it, save it as '
              'a PDF, or send it to yourself.',
              style: BxType.tiny(context.bx.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- pieces

  Widget _result() {
    final c = context.bx;
    final figure = _figure;

    if (figure == null) {
      return BxCard(
        padding: const EdgeInsets.all(BxSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BxEyebrow('Your figure'),
            const SizedBox(height: BxSpace.xs),
            Text('—', style: BxType.hero(c.muted)),
            const SizedBox(height: BxSpace.xs),
            Text(
              'Pick a grade for at least one course below and your GPA lands '
              'here as you type.',
              style: BxType.small(c.muted),
            ),
          ],
        ),
      );
    }

    final cls = _classify(figure, _scale);
    final scaleLabel = _scale == _Scale.five ? '5.00' : '4.00';

    return BxCard(
      accent: cls.accent,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BxEyebrow(
            _carriesPrevious ? 'Cumulative CGPA' : 'This semester GPA',
            color: cls.accent.ink(c),
          ),
          const SizedBox(height: BxSpace.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(figure.toStringAsFixed(2),
                  style: BxType.hero(cls.accent.ink(c))),
              const SizedBox(width: BxSpace.xs),
              Text('/ $scaleLabel', style: BxType.mono(c.muted, size: 14)),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          Text(cls.name, style: BxType.h2(c.ink)),
          const SizedBox(height: BxSpace.md),
          BxProgressBar(figure / _max, color: cls.accent.ink(c)),
          const SizedBox(height: BxSpace.md),
          Row(
            children: [
              Expanded(child: _fig('Total units', '$_figureUnits')),
              Expanded(
                child: _fig('Total points', _figurePoints.toStringAsFixed(1)),
              ),
              if (_carriesPrevious)
                Expanded(
                  child: _fig('This semester', _gpa!.toStringAsFixed(2)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fig(String label, String value) {
    final c = context.bx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: BxType.eyebrow(c.muted)),
        const SizedBox(height: 3),
        Text(value, style: BxType.mono(c.ink, size: 15, weight: 600)),
      ],
    );
  }

  Widget _scaleCard() {
    final c = context.bx;
    final points = _table.entries.map((e) => '${e.key}=${e.value}').join('  ');
    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Grading scale', style: BxType.bodyStrong(c.ink)),
              ),
              BxSegmented<_Scale>(
                value: _scale,
                options: const [
                  BxOption(_Scale.five, '5.0'),
                  BxOption(_Scale.four, '4.0'),
                ],
                onChanged: _setScale,
              ),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          Text(points, style: BxType.mono(c.muted, size: 12)),
        ],
      ),
    );
  }

  Widget _courseCard(int i) {
    final c = context.bx;
    final r = _rows[i];

    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: BxField(
                  label: 'Course ${i + 1}',
                  controller: r.name,
                  hint: 'e.g. CHM 101',
                  capitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: BxSpace.xs),
              IconButton(
                onPressed: _rows.length > 1 ? () => _removeRow(i) : null,
                icon: Icon(Icons.close_rounded, size: 19, color: c.muted),
                tooltip: 'Remove this course',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          Row(
            children: [
              Expanded(
                child: BxDropdown<int>(
                  label: 'Units',
                  value: r.units,
                  options: const [
                    BxOption(1, '1 unit'),
                    BxOption(2, '2 units'),
                    BxOption(3, '3 units'),
                    BxOption(4, '4 units'),
                    BxOption(5, '5 units'),
                    BxOption(6, '6 units'),
                  ],
                  onChanged: (v) => setState(() => r.units = v),
                ),
              ),
              const SizedBox(width: BxSpace.sm),
              Expanded(
                child: BxDropdown<String?>(
                  label: 'Grade',
                  value: r.grade,
                  hint: 'Pick',
                  options: [
                    for (final e in _table.entries)
                      BxOption<String?>(e.key, e.key,
                          subtitle: '${e.value} point${e.value == 1 ? '' : 's'} per unit'),
                  ],
                  onChanged: (v) => setState(() => r.grade = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previousCard() {
    final c = context.bx;
    final broken = _hasPrevious && !_carriesPrevious;

    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            value: _hasPrevious,
            onChanged: (v) => setState(() => _hasPrevious = v),
            contentPadding: EdgeInsets.zero,
            title: Text('I have a previous CGPA',
                style: BxType.bodyStrong(c.ink)),
            subtitle: Text(
              'Carry last session forward and see the cumulative figure.',
              style: BxType.tiny(c.muted),
            ),
            activeThumbColor: c.gold,
          ),
          if (_hasPrevious) ...[
            const SizedBox(height: BxSpace.xs),
            Row(
              children: [
                Expanded(
                  child: BxField(
                    label: 'Previous CGPA',
                    controller: _prevCgpaCtl,
                    hint: _scale == _Scale.five ? '3.85' : '3.10',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: BxSpace.sm),
                Expanded(
                  child: BxField(
                    label: 'Units so far',
                    controller: _prevUnitsCtl,
                    hint: '38',
                    keyboardType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (broken) ...[
              const SizedBox(height: BxSpace.xs),
              Text(
                'Fill both boxes — a CGPA between 0 and ${_max.toStringAsFixed(1)} '
                'and the units it was earned over — and it will be carried in.',
                style: BxType.tiny(c.warning),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
