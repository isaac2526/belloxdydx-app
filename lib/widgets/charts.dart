import 'dart:math';
import 'package:flutter/material.dart';

// Tiny hand-drawn charts, sharing the website's palette so the app
// and the site feel like one family.
const chartGold = Color(0xFFF5B301);
const chartBlue = Color(0xFF3EA0EE);
const chartGreen = Color(0xFF3ECF8E);
const chartViolet = Color(0xFF8B5CF6);

class AccuracyBar extends StatelessWidget {
  final int correct;
  final int wrong;
  const AccuracyBar({super.key, required this.correct, required this.wrong});
  @override
  Widget build(BuildContext context) {
    final total = max(1, correct + wrong);
    final pct = (correct / total * 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text("Accuracy ", style: const TextStyle(fontSize: 11)),
        Text("$pct%",
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: chartGreen)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          child: Row(children: [
            Expanded(flex: correct, child: Container(color: chartGreen)),
            Expanded(flex: max(1, wrong), child: Container(color: const Color(0xFFE5484D))),
          ]),
        ),
      ),
      const SizedBox(height: 3),
      Text("$correct correct · $wrong wrong",
          style: const TextStyle(fontSize: 10)),
    ]);
  }
}

class MiniBars extends StatelessWidget {
  final List<MapEntry<String, num>> data;
  final Color color;
  const MiniBars({super.key, required this.data, this.color = chartBlue});
  @override
  Widget build(BuildContext context) {
    final maxV = data.fold<num>(1, (m, e) => max(m, e.value));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: data
          .map((e) => Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 22,
                  height: 12 + 78 * (e.value / maxV),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [color, color.withOpacity(0.55)]),
                  ),
                ),
                const SizedBox(height: 4),
                Text(e.key,
                    style: const TextStyle(fontSize: 9),
                    overflow: TextOverflow.ellipsis),
              ]))
          .toList(),
    );
  }
}
