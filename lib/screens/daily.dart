import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';

// ⚡ The Daily Challenge — one question, once a day, drawn from THIS
// student's own courses. Answered state remembered on-device.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});
  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  Map<String, dynamic>? q;
  String? picked;
  bool done = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.daily();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString("bx_daily_${d["day"]}");
      if (mounted) {
        setState(() {
          q = d;
          picked = saved;
          done = saved != null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    }
  }

  Future<void> _answer(String k) async {
    if (done || q == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("bx_daily_${q!["day"]}", k);
    setState(() {
      picked = k;
      done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("⚡ Daily Challenge")),
      body: error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
          : q == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text("Today · ${q!["course"]}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: HtmlWidget("${q!["question_html"] ?? ""}"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...((q!["options"] as List?) ?? []).cast<Map>().map((o) {
                    final k = "${o["key"]}";
                    final correct = "${q!["correct_key"]}";
                    Color? tint;
                    if (done) {
                      if (k == correct) tint = const Color(0x3322C55E);
                      if (k == picked && picked != correct) tint = const Color(0x33EF4444);
                    }
                    return Card(
                      color: tint,
                      child: ListTile(
                        onTap: () => _answer(k),
                        leading: CircleAvatar(radius: 14, child: Text(k, style: const TextStyle(fontSize: 12))),
                        title: Text("${o["text"] ?? ""}"),
                      ),
                    );
                  }),
                  if (done) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: picked == "${q!["correct_key"]}" ? const Color(0x2222C55E) : const Color(0x22EF4444),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(picked == "${q!["correct_key"]}"
                              ? "✓ Correct! Come back tomorrow for a fresh one."
                              : "✗ The answer was ${q!["correct_key"]}. Tomorrow is another chance.",
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          if ((q!["explanation_html"] ?? "").toString().trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            HtmlWidget("${q!["explanation_html"]}"),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ]),
    );
  }
}
