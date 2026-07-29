import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../api.dart';
import '../watermark.dart';
import 'cbt_result.dart';

// The tests & exams hub. A live/timed exam runs on a SERVER clock:
// leaving the app does not pause it. Practice can pause; exams cannot.
class CbtListScreen extends StatefulWidget {
  const CbtListScreen({super.key});
  @override
  State<CbtListScreen> createState() => _CbtListScreenState();
}

class _CbtListScreenState extends State<CbtListScreen> {
  String status = "loading";
  List<Map<String, dynamic>> tests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => status = "loading");
    try {
      tests = await Api.fetchTests();
      setState(() => status = tests.isEmpty ? "empty" : "ready");
    } on ApiException catch (e) {
      setState(() => status = e.message == "not_activated" ? "locked" : "error");
    } catch (_) {
      setState(() => status = "error");
    }
  }

  String _courseCode(String courseId) {
    final courses = (Api.content?["courses"] as List?) ?? [];
    for (final c in courses) {
      if ((c as Map)["id"] == courseId) return "${c["code"]}";
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    Widget body;
    if (status == "loading") {
      body = const Center(child: CircularProgressIndicator());
    } else if (status == "locked") {
      body = const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text("🔑 Tests are premium. Activate your account to take them.",
                  textAlign: TextAlign.center)));
    } else if (status == "empty") {
      body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("No tests published yet."),
        const SizedBox(height: 10),
        FilledButton(onPressed: _load, child: const Text("Refresh")),
      ]));
    } else if (status == "error") {
      body = Center(
          child: FilledButton(onPressed: _load, child: const Text("Retry")));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text("Tests & Exams",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text("Timed exams run on a server clock. Leaving the app does not stop the timer.",
                style: TextStyle(color: hint, fontSize: 12)),
            const SizedBox(height: 14),
            ...tests.map((t) {
              final mode = "${t["mode"]}";
              final dur = t["duration_minutes"];
              final code = _courseCode("${t["course_id"]}");
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _openTest(t),
                  leading: Icon(
                    mode == "practice" ? Icons.fitness_center : Icons.timer,
                    color: const Color(0xFFF5B301),
                  ),
                  title: Text("${t["title"]}", style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    if (code.isNotEmpty) code,
                    if (t["question_count"] != null) "${t["question_count"]} questions",
                    if (mode != "practice" && dur != null) "$dur min",
                    mode == "practice" ? "can pause" : "timed",
                  ].join(" · ")),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            }),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text("Tests & Exams")), body: body);
  }

  Future<void> _openTest(Map<String, dynamic> t) async {
    final mode = "${t["mode"]}";
    if (mode != "practice") {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("${t["title"]}"),
          content: Text(
            "This is a TIMED ${mode == "exam" ? "exam" : "test"}. Once you start, the clock "
            "runs on our server and does NOT pause if you leave the app. "
            "Make sure you are ready.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Not yet")),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Start now")),
          ],
        ),
      );
      if (go != true) return;
    }
    try {
      final res = await Api.cbtStart("${t["id"]}");
      final attemptId = res["attemptId"] as String;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CbtExamScreen(attemptId: attemptId, title: "${t["title"]}")));
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class CbtExamScreen extends StatefulWidget {
  final String attemptId;
  final String title;
  const CbtExamScreen({super.key, required this.attemptId, required this.title});
  @override
  State<CbtExamScreen> createState() => _CbtExamScreenState();
}

class _CbtExamScreenState extends State<CbtExamScreen> with WidgetsBindingObserver {
  String status = "loading";
  List<Map> questions = [];
  Map<String, String> answers = {};
  int index = 0;
  DateTime? endsAt;
  bool timed = false;
  Timer? _ticker;
  Duration left = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to a live exam: re-sync the server clock at once.
    if (state == AppLifecycleState.resumed && timed) {
      _load(silent: true);
      Api.cbtViolation(widget.attemptId); // leaving a timed exam is logged
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => status = "loading");
    try {
      final feed = await Api.cbtFeed(widget.attemptId);
      if (feed["redirect"] == "results") {
        _showResult(null);
        return;
      }
      questions = ((feed["questions"] as List?) ?? []).cast<Map>();
      final ans = (feed["answers"] as Map?) ?? {};
      answers = ans.map((k, v) => MapEntry("$k", "$v"));
      final mode = "${(feed["test"] as Map?)?["mode"] ?? ""}";
      timed = mode == "exam" || mode == "test";
      if (feed["endsAt"] != null) {
        endsAt = DateTime.tryParse("${feed["endsAt"]}")?.toLocal();
        _startTicker();
      }
      setState(() => status = questions.isEmpty ? "empty" : "ready");
    } catch (_) {
      if (!silent) setState(() => status = "error");
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    if (endsAt == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = endsAt!.difference(DateTime.now());
      if (remaining.isNegative) {
        _ticker?.cancel();
        _autoSubmit();
      } else {
        setState(() => left = remaining);
      }
    });
  }

  Future<void> _save(String qid, String choice, String answerText) async {
    setState(() => answers[qid] = choice.isNotEmpty ? choice : answerText);
    await Api.cbtAnswer(widget.attemptId, qid, choice, answerText);
  }

  Future<void> _autoSubmit() async {
    if (!mounted) return;
    final j = await Api.cbtSubmit(widget.attemptId);
    _showResult(j);
  }

  Future<void> _submit() async {
    final unanswered = questions.where((q) => !answers.containsKey("${q["id"]}")).length;
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Submit now?"),
        content: Text(unanswered == 0
            ? "You answered every question. Submit for grading?"
            : "$unanswered question(s) still unanswered. Submit anyway?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Keep going")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Submit")),
        ],
      ),
    );
    if (go != true) return;
    setState(() => status = "loading");
    final j = await Api.cbtSubmit(widget.attemptId);
    _showResult(j);
  }

  void _showResult(Map<String, dynamic>? j) {
    if (!mounted) return;
    _ticker?.cancel();
    final score = j?["score"];
    final total = j?["total"];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Submitted \u2713"),
        content: Text(score != null
            ? "You scored $score out of $total.\n\nReview every question with the correct answers and explanations?"
            : "Your test has been submitted."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // dialog
              Navigator.pop(context); // exam screen
            },
            child: const Text("Done"),
          ),
          if (score != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // dialog
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CbtResultScreen(attemptId: widget.attemptId),
                  ),
                );
              },
              child: const Text("See corrections"),
            ),
        ],
      ),
    );
  }

  String get _wm {
    final me = (Api.content?["me"] as Map?) ?? {};
    return "${me["username"] ?? "belloxdydx"} · ${me["matric"] ?? ""}";
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    final s = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    return h > 0 ? "$h:$m:$s" : "$m:$s";
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (status == "loading") {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: CircularProgressIndicator()));
    }
    if (status == "error") {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(child: FilledButton(onPressed: () => _load(), child: const Text("Retry"))),
      );
    }
    if (status == "empty") {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: Text("No questions.")));
    }

    final q = questions[index];
    final options = ((q["options"] as List?) ?? []).cast<Map>();
    final qid = "${q["id"]}";
    final isText = options.isEmpty;
    final chosen = answers[qid];
    final onBg = Theme.of(context).textTheme.bodyLarge?.color;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (timed && endsAt != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(_fmt(left),
                    style: TextStyle(
                        color: left.inMinutes < 2 ? Colors.redAccent : const Color(0xFFF5B301),
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ),
            ),
        ],
      ),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text("Question ${index + 1} of ${questions.length}",
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HtmlWidget("${q["question_html"] ?? ""}",
                        textStyle: TextStyle(fontSize: 17, color: onBg)),
                    if (q["question_image_url"] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Image.network("${q["question_image_url"]}", errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (isText)
              TextField(
                controller: TextEditingController(text: chosen ?? "")
                  ..selection = TextSelection.collapsed(offset: (chosen ?? "").length),
                decoration: const InputDecoration(labelText: "Your answer"),
                onSubmitted: (v) => _save(qid, "", v),
                onChanged: (v) => answers[qid] = v,
              )
            else
              ...options.map((o) {
                final key = "${o["key"]}";
                final selected = chosen == key;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: selected ? const Color(0xFF23304D) : null,
                  child: ListTile(
                    onTap: () => _save(qid, key, ""),
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: selected ? const Color(0xFFF5B301) : Theme.of(context).colorScheme.surface,
                      child: Text(key,
                          style: TextStyle(
                              fontSize: 13,
                              color: selected ? const Color(0xFF0B1220) : onBg)),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((o["image_url"] ?? "").toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network("${o["image_url"]}",
                                  height: 120,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox()),
                            ),
                          ),
                        Text("${o["text"] ?? ""}"),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Row(
              children: [
                if (index > 0)
                  OutlinedButton(
                    onPressed: () => setState(() => index -= 1),
                    child: const Text("Previous"),
                  ),
                const Spacer(),
                if (index + 1 < questions.length)
                  FilledButton(
                    onPressed: () => setState(() => index += 1),
                    child: const Text("Next"),
                  )
                else
                  FilledButton(
                    onPressed: _submit,
                    child: const Text("Submit test"),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(questions.length, (i) {
                final answered = answers.containsKey("${questions[i]["id"]}");
                return GestureDetector(
                  onTap: () => setState(() => index = i),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: i == index
                        ? const Color(0xFFF5B301)
                        : answered
                            ? const Color(0xFF2E7D32)
                            : Theme.of(context).colorScheme.surface,
                    child: Text("${i + 1}", style: const TextStyle(fontSize: 12)),
                  ),
                );
              }),
            ),
          ],
        ),
        Positioned.fill(child: IgnorePointer(child: Watermark(text: _wm))),
      ]),
    );
  }
}
