import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../api.dart';

// 🩹 My Mistakes — every question that has ever beaten this student
// and not yet been avenged. Flip, learn, conquer.
class MistakesScreen extends StatefulWidget {
  const MistakesScreen({super.key});
  @override
  State<MistakesScreen> createState() => _MistakesScreenState();
}

class _MistakesScreenState extends State<MistakesScreen> {
  List<Map<String, dynamic>>? items;
  String? error;
  int i = 0;
  bool showAnswer = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.mistakes();
      if (mounted) setState(() => items = d);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🩹 My Mistakes")),
      body: error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!)))
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items!.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "Clean slate 🏆 No unavenged mistakes. Go practice and stay dangerous.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _deck(),
    );
  }

  Widget _deck() {
    final q = items![i];
    final options = ((q["options"] as List?) ?? []).cast<Map>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text("Card ${i + 1} of ${items!.length} · ${q["course"] ?? ""}",
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((q["question_image_url"] ?? "").toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Image.network("${q["question_image_url"]}",
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            HtmlWidget("${q["question_html"] ?? ""}"),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      ...options.map((o) {
        final k = "${o["key"]}";
        final correct = showAnswer && k == "${q["correct_key"]}";
        return Card(
          color: correct ? const Color(0x3322C55E) : null,
          child: ListTile(
            dense: true,
            leading: Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
            title: Text("${o["text"] ?? ""}"),
          ),
        );
      }),
      const SizedBox(height: 8),
      if (!showAnswer)
        FilledButton(
          onPressed: () => setState(() => showAnswer = true),
          child: const Text("Reveal the answer"),
        )
      else ...[
        if ((q["explanation_html"] ?? "").toString().trim().isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: HtmlWidget("${q["explanation_html"]}"),
            ),
          ),
      ],
      const SizedBox(height: 10),
      Row(children: [
        if (i > 0)
          OutlinedButton(
              onPressed: () => setState(() {
                    i -= 1;
                    showAnswer = false;
                  }),
              child: const Text("← Previous")),
        const Spacer(),
        if (i < items!.length - 1)
          FilledButton(
              onPressed: () => setState(() {
                    i += 1;
                    showAnswer = false;
                  }),
              child: const Text("Next card →")),
      ]),
      const SizedBox(height: 24),
    ]);
  }
}
