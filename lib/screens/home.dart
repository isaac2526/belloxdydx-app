import 'package:flutter/material.dart';
import '../api.dart';
import 'course.dart';
import 'practice.dart';

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

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text("Hi, ${me["first_name"] ?? "champ"} 👋",
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text("Pick a course and smash it.",
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
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
