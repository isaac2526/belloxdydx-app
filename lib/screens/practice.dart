import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../api.dart';

class PracticeScreen extends StatefulWidget {
  final String courseId;
  final String courseCode;
  const PracticeScreen(
      {super.key, required this.courseId, required this.courseCode});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  String status = "loading";
  String? attemptId;
  List<Map> questions = [];
  int index = 0;
  Map<String, dynamic>? feedback;
  final answerCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      attemptId = await Api.practiceStart(widget.courseId);
      final feed = await Api.practiceFeed(attemptId!);
      questions = ((feed["questions"] as List?) ?? []).cast<Map>();
      index = ((feed["attempt"] as Map?)?["current_index"] as num?)
              ?.toInt() ??
          0;
      if (index >= questions.length) index = 0;
      setState(
          () => status = questions.isEmpty ? "empty" : "question");
    } on ApiException catch (e) {
      setState(() =>
          status = e.message == "not_activated" ? "locked" : "error");
    } catch (_) {
      setState(() => status = "error");
    }
  }

  Future<void> _answer(String choice) async {
    final q = questions[index];
    setState(() => status = "checking");
    try {
      final j = await Api.practiceAnswer(
          attemptId!, "${q["id"]}", choice, answerCtl.text.trim());
      setState(() {
        feedback = j;
        status = "feedback";
      });
    } catch (_) {
      setState(() => status = "question");
    }
  }

  Future<void> _next() async {
    answerCtl.clear();
    feedback = null;
    if (index + 1 >= questions.length) {
      setState(() => status = "checking");
      try {
        final j = await Api.practiceFinish(attemptId!);
        if (!mounted) return;
        await showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text("Practice finished 🎉"),
                  content: Text(
                      "You scored ${j["score"]} out of ${j["total"]}."),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Sweet"))
                  ],
                ));
        if (mounted) Navigator.pop(context);
      } catch (_) {
        if (mounted) Navigator.pop(context);
      }
      return;
    }
    setState(() {
      index += 1;
      status = "question";
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (status == "loading" || status == "checking") {
      body = const Center(child: CircularProgressIndicator());
    } else if (status == "locked") {
      body = const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  "🔑 Practice is premium. Activate your account to train.",
                  textAlign: TextAlign.center)));
    } else if (status == "empty") {
      body = const Center(
          child: Text("No questions in this course yet."));
    } else if (status == "error") {
      body = Center(
          child: FilledButton(
              onPressed: () {
                setState(() => status = "loading");
                _start();
              },
              child: const Text("Retry")));
    } else {
      final q = questions[index];
      final options = ((q["options"] as List?) ?? []).cast<Map>();
      final isText = options.isEmpty;
      final fb = feedback;
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Question ${index + 1} of ${questions.length}",
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: HtmlWidget("${q["question_html"] ?? ""}",
                  textStyle:
                      const TextStyle(fontSize: 17, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          if (fb == null) ...[
            if (isText) ...[
              TextField(
                  controller: answerCtl,
                  decoration:
                      const InputDecoration(labelText: "Your answer")),
              const SizedBox(height: 10),
              FilledButton(
                  onPressed: () => _answer(""),
                  child: const Text("Submit answer")),
            ] else
              ...options.map((o) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _answer("${o["key"]}"),
                      leading: CircleAvatar(
                          radius: 15,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          child: Text("${o["key"]}",
                              style: const TextStyle(fontSize: 13))),
                      title: Text("${o["text"] ?? ""}"),
                    ),
                  )),
          ] else ...[
            Card(
              color: fb["correct"] == true
                  ? const Color(0xFF14331F)
                  : const Color(0xFF3A1620),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fb["correct"] == true ? "Correct ✓" : "Not quite ✗",
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    if (fb["correctKey"] != null &&
                        "${fb["correctKey"]}".isNotEmpty)
                      Text("Correct answer: ${fb["correctKey"]}"),
                    if (fb["correctAnswerText"] != null)
                      Text("Answer: ${fb["correctAnswerText"]}"),
                    if (fb["explanationHtml"] != null &&
                        "${fb["explanationHtml"]}".trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      HtmlWidget("${fb["explanationHtml"]}",
                          textStyle: TextStyle(color: Theme.of(context).hintColor)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
                onPressed: _next,
                child: Text(index + 1 >= questions.length
                    ? "Finish"
                    : "Next question")),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text("Practice · ${widget.courseCode}")),
      body: body,
    );
  }
}
