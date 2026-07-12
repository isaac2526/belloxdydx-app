import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../theme.dart';
import 'announcements.dart';
import 'course.dart';
import 'practice.dart';
import 'cbt.dart';
import 'cbt_result.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tab)? onGoTab;
  const HomeScreen({super.key, this.onGoTab});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool busy = false;
  Map<String, dynamic> home = {};
  bool loadingHome = true;

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  Future<void> _loadHome() async {
    final h = await Api.fetchHome();
    if (mounted) {
      setState(() {
        home = h;
        loadingHome = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() => busy = true);
    try {
      await Api.fetchContent();
    } catch (_) {}
    await _loadHome();
    if (mounted) setState(() => busy = false);
  }

  Duration _toMarathon() {
    final iso = "${home["marathonIso"] ?? ""}";
    final target = DateTime.tryParse(iso) ?? DateTime(2026, 12, 1, 9);
    final d = target.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  Widget build(BuildContext context) {
    final c = Api.content;
    final gold = const Color(0xFFF5B301);
    final navy = const Color(0xFF0B1220);
    final theme = context.watch<ThemeController>();
    // Cards adapt to theme so text never hides on light mode.
    final cardColor = Theme.of(context).cardColor;
    final onCard = Theme.of(context).textTheme.bodyLarge?.color;

    if (c == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Could not load. Check your network."),
            const SizedBox(height: 10),
            FilledButton(
                onPressed: busy ? null : _reload, child: const Text("Retry")),
          ],
        ),
      );
    }
    final courses = (c["courses"] as List?) ?? [];
    final materials = (c["materials"] as List?) ?? [];
    final me = (c["me"] as Map?) ?? {};
    final firstName = home["firstName"] ?? me["first_name"] ?? "champ";

    final unread = ((c["announcements"] as List?) ?? [])
        .where((a) => (a as Map)["unread"] == true)
        .length;

    final streak = (home["streak"] as Map?) ?? {};
    final quote = (home["quote"] as Map?) ?? {};
    final resume = home["resume"] as Map?;
    final md = _toMarathon();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text("Belloxdydx"),
        actions: [
          IconButton(
            tooltip: theme.isDark ? "Light mode" : "Dark mode",
            icon: Icon(theme.isDark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            onPressed: () => theme.toggle(),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: "Announcements",
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AnnouncementsScreen())),
              ),
              if (unread > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.redAccent, shape: BoxShape.circle),
                    child: Text("$unread",
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white)),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------- greeting ----------
            Text("Good day, $firstName 👋",
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text("Small daily reading beats midnight panic. Let's move.",
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 14),

            // ---------- security strip ----------
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withOpacity(0.35)),
              ),
              child: const Row(children: [
                Icon(Icons.shield, color: Colors.redAccent, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Screenshots & screen recording are DETECTED. Any capture freezes your account. Every page carries your name and matric.",
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),

            // ---------- resume card (verified) ----------
            if (resume != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: gold.withOpacity(0.5)),
                ),
                child: ListTile(
                  onTap: () {
                    final id = "${resume["id"]}";
                    if (resume["kind"] == "cbt") {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CbtExamScreen(
                              attemptId: id, title: "Continue exam")));
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PracticeScreen(
                              resumeAttemptId: id,
                              courseId: "",
                              courseCode:
                                  "${resume["courseCode"] ?? "Practice"}")));
                    }
                  },
                  leading: Icon(Icons.play_circle_fill, color: gold, size: 34),
                  title: const Text("Continue where you stopped",
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      "${resume["courseCode"] ?? ""} · your progress is saved"),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),

            // ---------- Tests & Exams ----------
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: cardColor,
              child: ListTile(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CbtListScreen())),
                leading: Icon(Icons.timer, color: gold),
                title: Text("Tests & Exams",
                    style:
                        TextStyle(fontWeight: FontWeight.w700, color: onCard)),
                subtitle: Text("Timed CBT you can take right here",
                    style: TextStyle(color: Theme.of(context).hintColor)),
                trailing: Icon(Icons.chevron_right, color: onCard),
              ),
            ),

            // ---------- Ask Bello AI ----------
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: cardColor,
              child: ListTile(
                onTap: () => widget.onGoTab?.call(2),
                leading: Icon(Icons.smart_toy_outlined, color: gold),
                title: Text("Ask Bello AI",
                    style:
                        TextStyle(fontWeight: FontWeight.w700, color: onCard)),
                subtitle: Text(
                    "Your 24/7 tutor. Explanations, solved questions, summaries.",
                    style: TextStyle(color: Theme.of(context).hintColor)),
                trailing: Icon(Icons.chevron_right, color: onCard),
              ),
            ),

            // ---------- streak + quote row ----------
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Card(
                    color: cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("STUDY STREAK",
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1,
                                  color: Theme.of(context).hintColor)),
                          const SizedBox(height: 6),
                          Row(children: [
                            const Text("🔥", style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 6),
                            Text("${streak["current"] ?? 0}",
                                style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: onCard)),
                            const SizedBox(width: 4),
                            Text("days",
                                style: TextStyle(
                                    color: Theme.of(context).hintColor)),
                          ]),
                          const SizedBox(height: 4),
                          Text("Best: ${streak["best"] ?? 0} days",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).hintColor)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if ((quote["content"] ?? "").toString().isNotEmpty)
              Card(
                color: cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("QUOTE OF THE MOMENT",
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: Theme.of(context).hintColor)),
                      const SizedBox(height: 8),
                      Text("\u201C${quote["content"]}\u201D",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              color: onCard)),
                      const SizedBox(height: 8),
                      Text("— ${quote["author"] ?? "Belloxdydx"}",
                          style:
                              TextStyle(color: Theme.of(context).hintColor)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),

            // ---------- marathon countdown ----------
            Card(
              color: cardColor,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("MARATHON COUNTDOWN",
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            color: Theme.of(context).hintColor)),
                    const SizedBox(height: 4),
                    Text("December is for history!!!",
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: onCard)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _timeCell(md.inDays, "DAYS", onCard, gold),
                        _timeCell(md.inHours % 24, "HOURS", onCard, gold),
                        _timeCell(md.inMinutes % 60, "MINS", onCard, gold),
                        _timeCell(md.inSeconds % 60, "SECS", onCard, gold),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("168 hours of lectures. See y'all in December.",
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ---------- your courses ----------
            Text("YOUR COURSES",
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            ...courses.map((co) {
              final m = co as Map;
              final count = materials
                  .where((x) => (x as Map)["course_id"] == m["id"])
                  .length;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: cardColor,
                child: Column(
                  children: [
                    ListTile(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => CourseScreen(course: m))),
                      leading: CircleAvatar(
                        backgroundColor: gold,
                        child: Text(
                            (m["code"] ?? "?")
                                .toString()
                                .split(" ")
                                .first
                                .substring(0, 1),
                            style: TextStyle(
                                color: navy, fontWeight: FontWeight.w800)),
                      ),
                      title: Text("${m["code"]}",
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: onCard)),
                      subtitle: Text("${m["title"]} · $count materials",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: Theme.of(context).hintColor)),
                      trailing: Icon(Icons.chevron_right, color: onCard),
                    ),
                    // Practice button under EVERY course, like the website.
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => PracticeScreen(
                                      courseId: "${m["id"]}",
                                      courseCode: "${m["code"]}"))),
                          icon: Icon(Icons.quiz, color: gold, size: 18),
                          label: Text("Practice ${m["code"]} questions",
                              style: TextStyle(color: onCard)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: gold.withOpacity(0.5)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _timeCell(int value, String label, Color? onCard, Color gold) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(value.toString().padLeft(2, "0"),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, color: onCard)),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor)),
      ],
    );
  }
}
