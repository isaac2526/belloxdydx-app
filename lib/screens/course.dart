import 'package:flutter/material.dart';
import '../api.dart';
import 'viewer.dart';

const typeNames = {
  "note": "📖 Notes",
  "slide": "📊 Slides",
  "video": "🎬 Videos",
  "series": "📚 Series",
};

class CourseScreen extends StatelessWidget {
  final Map course;
  const CourseScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final materials = ((Api.content?["materials"] as List?) ?? [])
        .where((m) => (m as Map)["course_id"] == course["id"])
        .cast<Map>()
        .toList();

    final byType = <String, List<Map>>{};
    for (final m in materials) {
      byType.putIfAbsent("${m["type"]}", () => []).add(m);
    }

    return Scaffold(
      appBar: AppBar(title: Text("${course["code"]}")),
      body: materials.isEmpty
          ? const Center(
              child: Text("No materials here yet. Check back soon."))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text("${course["title"]}",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final t in ["note", "slide", "video", "series"])
                  if (byType[t] != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(typeNames[t] ?? t,
                          style: const TextStyle(
                              color: Color(0xFFF5B301),
                              fontWeight: FontWeight.w700)),
                    ),
                    ...byType[t]!.map((m) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => ViewerScreen(
                                        materialId: "${m["id"]}",
                                        title: "${m["title"]}",
                                        type: "${m["type"]}"))),
                            title: Text("${m["title"]}",
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            subtitle: m["duration_label"] != null
                                ? Text("${m["duration_label"]}")
                                : null,
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        )),
                  ],
              ],
            ),
    );
  }
}
