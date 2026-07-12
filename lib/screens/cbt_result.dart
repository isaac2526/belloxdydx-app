import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../api.dart';
import '../watermark.dart';

// The full post exam review, mirroring the website: score header, then
// every question with the options, the student's pick, the correct
// answer, and the explanation. Turns a bare score into real learning.
class CbtResultScreen extends StatefulWidget {
  final String attemptId;
  const CbtResultScreen({super.key, required this.attemptId});
  @override
  State<CbtResultScreen> createState() => _CbtResultScreenState();
}

class _CbtResultScreenState extends State<CbtResultScreen> {
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.cbtResult(widget.attemptId);
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiException ? e.message : "Could not load.");
      }
    }
  }

  String get _wm {
    final me = (Api.content?["me"] as Map?) ?? {};
    return "${me["username"] ?? "belloxdydx"} · ${me["matric"] ?? ""}";
  }

  @override
  Widget build(BuildContext context) {
    final gold = const Color(0xFFF5B301);
    final green = const Color(0xFF3ECF8E);
    final red = const Color(0xFFFF5A67);
    final onBg = Theme.of(context).textTheme.bodyLarge?.color;

    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Result")),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error!, textAlign: TextAlign.center),
        )),
      );
    }
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Result")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final score = data!["score"] ?? 0;
    final total = data!["total"] ?? 0;
    final items = (data!["items"] as List?) ?? [];
    final pct = total > 0 ? ((score / total) * 100).round() : 0;

    return Scaffold(
      appBar: AppBar(title: Text("${data!["title"] ?? "Result"}")),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // score header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: gold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: gold.withOpacity(0.5)),
              ),
              child: Column(children: [
                Text("YOUR SCORE",
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        color: Theme.of(context).hintColor)),
                const SizedBox(height: 6),
                Text("$score / $total",
                    style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: onBg)),
                Text("$pct%",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: pct >= 50 ? green : red)),
              ]),
            ),
            const SizedBox(height: 8),
            Text("Corrections",
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 4),

            ...items.map((raw) {
              final q = raw as Map;
              final opts = (q["options"] as List?) ?? [];
              final correct = "${q["correct_key"]}";
              final yours = q["your_key"]?.toString();
              final isCorrect = q["is_correct"] == true;
              final expl = "${q["explanation_html"] ?? ""}";

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: (isCorrect ? green : red).withOpacity(0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(isCorrect ? Icons.check : Icons.close,
                              size: 16, color: isCorrect ? green : red),
                        ),
                        const SizedBox(width: 8),
                        Text("Question ${q["n"]}",
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 8),
                      HtmlWidget("${q["question_html"]}",
                          textStyle: TextStyle(fontSize: 15, color: onBg)),
                      const SizedBox(height: 10),
                      ...opts.map((o) {
                        final op = o as Map;
                        final key = "${op["key"]}";
                        final isRight = key == correct;
                        final isYours = key == yours;
                        Color? bg;
                        Color? bd;
                        if (isRight) {
                          bg = green.withOpacity(0.14);
                          bd = green;
                        } else if (isYours && !isCorrect) {
                          bg = red.withOpacity(0.12);
                          bd = red;
                        }
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: bd ??
                                    Theme.of(context).dividerColor),
                          ),
                          child: Row(children: [
                            Text("$key. ",
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, color: onBg)),
                            Expanded(
                                child: Text("${op["text"] ?? ""}",
                                    style: TextStyle(color: onBg))),
                            if (isRight)
                              Text("Correct",
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: green)),
                            if (isYours && !isCorrect)
                              Text("Your pick",
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: red)),
                          ]),
                        );
                      }),
                      if (expl.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: green.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: green.withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Why",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: green)),
                              const SizedBox(height: 4),
                              HtmlWidget(expl,
                                  textStyle: TextStyle(
                                      fontSize: 13, color: onBg)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text("Done"),
            ),
          ],
        ),
        Positioned.fill(child: IgnorePointer(child: Watermark(text: _wm))),
      ]),
    );
  }
}
