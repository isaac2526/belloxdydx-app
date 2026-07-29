import 'package:flutter/material.dart';

// The classic UI companion: units in, grades in, GPA out. Fully
// offline — no account needed, lives quietly in the menu.
class CgpaScreen extends StatefulWidget {
  const CgpaScreen({super.key});
  @override
  State<CgpaScreen> createState() => _CgpaScreenState();
}

class _Row {
  int units = 3;
  String grade = "A";
}

const _points = {"A": 5, "B": 4, "C": 3, "D": 2, "E": 1, "F": 0};

class _CgpaScreenState extends State<CgpaScreen> {
  final rows = <_Row>[_Row(), _Row(), _Row(), _Row()];

  double get gpa {
    var qp = 0;
    var units = 0;
    for (final r in rows) {
      qp += r.units * (_points[r.grade] ?? 0);
      units += r.units;
    }
    return units == 0 ? 0 : qp / units;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("CGPA Calculator")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text("Your GPA", style: TextStyle(fontSize: 12)),
                Text(gpa.toStringAsFixed(2),
                    style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFF5B301))),
                Text(
                  gpa >= 4.5
                      ? "First Class pace 🔥"
                      : gpa >= 3.5
                          ? "Second Class Upper — push small more"
                          : gpa >= 2.4
                              ? "Second Class Lower — the climb continues"
                              : "Every point is winnable. Practice dey pay.",
                  style: const TextStyle(fontSize: 12),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          ...rows.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Text("Course ${i + 1}",
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  DropdownButton<int>(
                    value: r.units,
                    items: [1, 2, 3, 4, 5, 6]
                        .map((u) => DropdownMenuItem(
                            value: u, child: Text("$u units")))
                        .toList(),
                    onChanged: (v) => setState(() => r.units = v ?? 3),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: r.grade,
                    items: _points.keys
                        .map((g) =>
                            DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => r.grade = v ?? "A"),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: rows.length <= 1
                        ? null
                        : () => setState(() => rows.removeAt(i)),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => rows.add(_Row())),
            icon: const Icon(Icons.add),
            label: const Text("Add course"),
          ),
        ],
      ),
    );
  }
}
