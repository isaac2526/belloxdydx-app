import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../theme.dart';
import 'announcements.dart';
import 'course.dart';
import 'practice.dart';
import 'cbt.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool busy = false;

  Future<void> _reload() async {
    setState(() => busy = true);
    try {
      await Api.fetchContent();
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Api.content;
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

    final unread = ((c["announcements"] as List?) ?? [])
        .where((a) => (a as Map)["unread"] == true)
        .length;
    final theme = context.watch<ThemeController>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text("Belloxdydx"),
        actions: [
          IconButton(
            tooltip: theme.isDark ? "Light mode" : "Dark mode",
            icon: Icon(theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => theme.toggle(),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: "Announcements",
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
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
                        style: const TextStyle(fontSize: 9, color: Colors.white)),
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
            Text("Hi, ${me["first_name"] ?? "champ"} 👋",
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text("Pick a course and smash it.",
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 14),
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 14),
              color: const Color(0xFF17233D),
              child: ListTile(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CbtListScreen())),
                leading: const Icon(Icons.timer, color: Color(0xFFF5B301)),
                title: const Text("Tests & Exams",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text("Timed CBT you can take right here"),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 2),
            ...courses.map((co) {
              final m = co as Map;
              final count = materials
                  .where((x) => (x as Map)["course_id"] == m["id"])
                  .length;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CourseScreen(course: m))),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFF5B301),
                    child: Text(
                        (m["code"] ?? "?").toString().split(" ").first
                            .substring(0, 1),
                        style: const TextStyle(
                            color: Color(0xFF0B1220),
                            fontWeight: FontWeight.w800)),
                  ),
                  title: Text("${m["code"]}",
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text("${m["title"]} · $count materials",
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.quiz, color: Color(0xFFF5B301)),
                    tooltip: "Practice questions",
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => PracticeScreen(
                                courseId: "${m["id"]}",
                                courseCode: "${m["code"]}"))),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
