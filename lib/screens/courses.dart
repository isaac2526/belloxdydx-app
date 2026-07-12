import 'package:flutter/material.dart';
import '../api.dart';
import 'course.dart';
import 'practice.dart';

// Courses get their own home again, first class, split by semester,
// searchable, and refreshable with a pull.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});
  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  String query = "";
  bool busy = false;

  Future<void> _reload() async {
    setState(() => busy = true);
    try {
      await Api.fetchContent();
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  String _semLabel(dynamic sem) {
    final s = "${sem ?? ""}".toLowerCase();
    if (s.startsWith("2") || s.contains("second")) return "SECOND SEMESTER";
    if (s.startsWith("1") || s.contains("first")) return "FIRST SEMESTER";
    return "OTHER COURSES";
  }

  @override
  Widget build(BuildContext context) {
    final gold = const Color(0xFFF5B301);
    final navy = const Color(0xFF0B1220);
    final onCard = Theme.of(context).textTheme.bodyLarge?.color;
    final hint = Theme.of(context).hintColor;

    final c = Api.content;
    final allCourses = ((c?["courses"] as List?) ?? []).cast<Map>();
    final materials = (c?["materials"] as List?) ?? [];

    final courses = allCourses.where((m) {
      if (query.trim().isEmpty) return true;
      final q = query.toLowerCase();
      return "${m["code"]}".toLowerCase().contains(q) ||
          "${m["title"]}".toLowerCase().contains(q);
    }).toList();

    // Group into semesters, first semester first.
    final groups = <String, List<Map>>{};
    for (final m in courses) {
      groups.putIfAbsent(_semLabel(m["semester"]), () => []).add(m);
    }
    final order = ["FIRST SEMESTER", "SECOND SEMESTER", "OTHER COURSES"];
    final sections = order.where((k) => groups.containsKey(k)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Courses"),
        actions: [
          IconButton(
            tooltip: "Refresh",
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: busy ? null : _reload,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: "Search a course, e.g. MAT 101",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              ),
            ),
            const SizedBox(height: 16),

            if (allCourses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  Icon(Icons.menu_book_outlined, size: 40, color: hint),
                  const SizedBox(height: 10),
                  Text("No courses loaded yet.",
                      style: TextStyle(color: hint)),
                  const SizedBox(height: 10),
                  FilledButton(
                      onPressed: _reload, child: const Text("Refresh")),
                ]),
              )
            else if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child: Text("No course matches \"$query\".",
                        style: TextStyle(color: hint))),
              ),

            for (final section in sections) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                        color: gold, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 8),
                  Text(section,
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: hint)),
                  const SizedBox(width: 8),
                  Text("${groups[section]!.length}",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: gold)),
                ]),
              ),
              ...groups[section]!.map((m) {
                final count = materials
                    .where((x) => (x as Map)["course_id"] == m["id"])
                    .length;
                final code = "${m["code"]}";
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(children: [
                    ListTile(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CourseScreen(course: m))),
                      leading: CircleAvatar(
                        backgroundColor: gold,
                        child: Text(
                            code.isEmpty ? "?" : code.substring(0, 1),
                            style: TextStyle(
                                color: navy, fontWeight: FontWeight.w800)),
                      ),
                      title: Text(code,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: onCard)),
                      subtitle: Text("${m["title"]} · $count materials",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: hint)),
                      trailing: Icon(Icons.chevron_right, color: onCard),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        CourseScreen(course: m))),
                            icon: const Icon(Icons.folder_open, size: 17),
                            label: const Text("Materials"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => PracticeScreen(
                                        courseId: "${m["id"]}",
                                        courseCode: code))),
                            icon: const Icon(Icons.quiz, size: 17),
                            label: const Text("Practice"),
                            style: FilledButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: navy),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                );
              }),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}
