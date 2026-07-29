import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../api.dart';

// WHO WANTS TO BE A BELLOXDYDX MILLIONAIRE? — the app edition.
// The Clock (15/30/45s), 50:50, real Ask-the-Class, Switch, two
// safety nets, fresh random questions every game.
const _ladder = [1000,2000,3000,5000,8000,15000,30000,50000,75000,125000,200000,300000,500000,750000,1000000];
const _safe = [4, 9];
String _fmt(int n) => "₦${n.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+$)"), (m) => "${m[1]},")}";

class MillionaireScreen extends StatefulWidget {
  const MillionaireScreen({super.key});
  @override
  State<MillionaireScreen> createState() => _MillionaireScreenState();
}

class _MillionaireScreenState extends State<MillionaireScreen> {
  List<Map<String, dynamic>>? qs;
  final picked = <String>{};
  int i = 0;
  int spareAt = 15;
  String? choice;
  String phase = "idle"; // idle | locked | revealed
  final dead = <String>{};
  Map<String, dynamic>? poll;
  bool usedFifty = false, usedClass = false, usedSwitch = false;
  Map<String, dynamic>? over;
  int left = 15;
  Timer? tick;
  bool busy = false;
  String? error;

  int _timeFor(int idx) => idx < 5 ? 15 : idx < 10 ? 30 : 45;

  void _startClock() {
    tick?.cancel();
    left = _timeFor(i);
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        left -= 1;
        if (left <= 0) {
          tick?.cancel();
          phase = "revealed";
          choice = null;
          Future.delayed(const Duration(milliseconds: 1100), () => _fall(true));
        }
      });
    });
  }

  void _fall(bool timeUp) {
    final lastSafe = _safe.lastWhere((s) => s < i, orElse: () => -1);
    final won = lastSafe >= 0 ? _ladder[lastSafe] : 0;
    Api.millionaireReport(won, false);
    if (mounted) {
      setState(() => over = {"won": won, "crowned": false, "fell": true, "timeUp": timeUp});
    }
  }

  Future<void> _start() async {
    setState(() { busy = true; error = null; });
    try {
      final deal = await Api.millionaireStart(picked.toList());
      setState(() {
        qs = deal;
        i = 0; spareAt = 15; choice = null; phase = "idle";
        dead.clear(); poll = null;
        usedFifty = usedClass = usedSwitch = false;
        over = null;
      });
      _startClock();
    } catch (e) {
      setState(() => error = friendly(e));
    } finally {
      setState(() => busy = false);
    }
  }

  void _lockIn(String k) {
    final q = qs![i];
    if (phase != "idle" || dead.contains(k)) return;
    tick?.cancel();
    setState(() { choice = k; phase = "locked"; });
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      setState(() => phase = "revealed");
      final right = k == "${q["correct_key"]}";
      Future.delayed(const Duration(milliseconds: 1300), () {
        if (!mounted) return;
        if (right) {
          if (i == 14) {
            Api.millionaireReport(_ladder[14], true);
            setState(() => over = {"won": _ladder[14], "crowned": true, "fell": false});
          }
        } else {
          _fall(false);
        }
      });
    });
  }

  void _next() {
    setState(() {
      choice = null; phase = "idle"; dead.clear(); poll = null; i += 1;
    });
    _startClock();
  }

  void _walk() {
    tick?.cancel();
    final won = i > 0 ? _ladder[i - 1] : 0;
    Api.millionaireReport(won, false);
    setState(() => over = {"won": won, "crowned": false, "fell": false});
  }

  void _fifty() {
    final q = qs![i];
    if (usedFifty || phase != "idle") return;
    final wrong = ((q["options"] as List).cast<Map>())
        .map((o) => "${o["key"]}")
        .where((k) => k != "${q["correct_key"]}")
        .toList()..shuffle(Random());
    setState(() { dead.addAll(wrong.take(2)); usedFifty = true; });
  }

  Future<void> _askClass() async {
    final q = qs![i];
    if (usedClass || phase != "idle") return;
    setState(() => usedClass = true);
    final p = await Api.millionairePoll("${q["id"]}");
    if (mounted) setState(() => poll = p);
  }

  void _switch() {
    if (usedSwitch || phase != "idle" || spareAt >= (qs?.length ?? 0)) return;
    setState(() {
      qs![i] = qs![spareAt];
      spareAt += 1;
      dead.clear(); poll = null;
      usedSwitch = true;
      left = _timeFor(i);
    });
    _startClock();
  }

  @override
  void dispose() { tick?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A0F2C);
    const gold = Color(0xFFF5B301);
    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text("BELLOXDYDX MILLIONAIRE",
            style: TextStyle(fontSize: 14, letterSpacing: 1, fontWeight: FontWeight.w800)),
      ),
      body: over != null
          ? _overView(gold)
          : qs == null
              ? _pickView(gold)
              : _stageView(gold),
    );
  }

  Widget _pickView(Color gold) {
    final courses = ((Api.content?["courses"] as List?) ?? []).cast<Map>();
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Text("💺", textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
      const Text("WHO WANTS TO BE A\nBELLOXDYDX MILLIONAIRE?",
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFF5B301), fontSize: 20, fontWeight: FontWeight.w900, height: 1.2)),
      const SizedBox(height: 8),
      const Text(
        "15 questions against the clock — 15s, 30s, then 45s as the money grows. Two safety nets 🛡, three real lifelines. Pick at least 6 courses.",
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF9FB0CC), fontSize: 12),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
        children: courses.map((c) {
          final id = "${c["id"]}";
          final on = picked.contains(id);
          return ChoiceChip(
            label: Text("${c["code"]}"),
            selected: on,
            selectedColor: gold,
            labelStyle: TextStyle(color: on ? const Color(0xFF0B1220) : Colors.white, fontWeight: FontWeight.w700),
            backgroundColor: const Color(0xFF141C4D),
            onSelected: (_) => setState(() => on ? picked.remove(id) : picked.add(id)),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      Text("${picked.length} of 6 minimum selected",
          textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9FB0CC), fontSize: 12)),
      const SizedBox(height: 8),
      FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: gold, foregroundColor: const Color(0xFF0B1220),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        onPressed: picked.length < 6 || busy ? null : _start,
        child: Text(busy ? "Setting the stage…" : "TAKE THE HOT SEAT"),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFCA5A5))),
        ),
    ]);
  }

  Widget _stageView(Color gold) {
    final q = qs![i];
    final options = ((q["options"] as List?) ?? []).cast<Map>();
    final total = _timeFor(i);
    final ring = left <= 5 ? const Color(0xFFEF4444) : left <= 10 ? const Color(0xFFF59E0B) : const Color(0xFF3ECF8E);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        SizedBox(
          width: 58, height: 58,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: left / total, strokeWidth: 5,
              color: ring, backgroundColor: const Color(0xFF1C2766),
            ),
            Text("$left", style: TextStyle(color: ring, fontWeight: FontWeight.w900, fontSize: 18)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Question ${i + 1} of 15 · ${q["course"] ?? ""}",
                style: const TextStyle(color: Color(0xFF8DA0D9), fontSize: 11)),
            Text(_fmt(_ladder[i]),
                style: const TextStyle(color: Color(0xFFF5B301), fontSize: 22, fontWeight: FontWeight.w900)),
          ]),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFFD4AF37))),
          onPressed: phase == "idle" ? _walk : null,
          child: Text("🚶 ${_fmt(i > 0 ? _ladder[i - 1] : 0)}", style: const TextStyle(fontSize: 11)),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: List.generate(_ladder.length, (idx) {
        final here = idx == i; final passed = idx < i; final safeStop = _safe.contains(idx);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: here ? gold : passed ? const Color(0x403ECF8E) : const Color(0x14FFFFFF),
          ),
          child: Text("${safeStop ? "🛡" : ""}${_fmt(_ladder[idx])}",
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  color: here ? const Color(0xFF0B1220) : safeStop ? gold : const Color(0xFFB9C6E8))),
        );
      })),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _life("50:50", usedFifty, _fifty),
        const SizedBox(width: 8),
        _life("👥 Ask the Class", usedClass, _askClass),
        const SizedBox(width: 8),
        _life("🔁 Switch", usedSwitch, _switch),
      ]),
      if (poll != null) _pollView(options),
      const SizedBox(height: 12),
      _hex(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((q["question_image_url"] ?? "").toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network("${q["question_image_url"]}",
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          HtmlWidget("${q["question_html"] ?? ""}",
              textStyle: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
        state: "idle",
      ),
      const SizedBox(height: 10),
      ...options.map((o) {
        final k = "${o["key"]}";
        String state;
        if (phase == "revealed") {
          state = k == "${q["correct_key"]}" ? "right" : k == choice ? "wrong" : "dead";
        } else if (phase == "locked") {
          state = k == choice ? "picked" : "dead";
        } else {
          state = dead.contains(k) ? "dead" : "idle";
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => _lockIn(k),
            child: _hex(
              state: state,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("$k. ", style: TextStyle(color: state == "idle" ? gold : Colors.white, fontWeight: FontWeight.w900)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((o["image_url"] ?? "").toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network("${o["image_url"]}",
                              height: 110, errorBuilder: (_, __, ___) => const SizedBox()),
                        ),
                      ),
                    Text("${o["text"] ?? ""}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }),
      if (phase == "locked")
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text("Final answer… 🥁", textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFF5B301), fontWeight: FontWeight.w700)),
        ),
      if (phase == "revealed" && choice == "${q["correct_key"]}" && over == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: const Color(0xFF0B1220)),
            onPressed: _next,
            child: Text("✓ CORRECT! Next → ${_fmt(i + 1 < 15 ? _ladder[i + 1] : _ladder[14])}"),
          ),
        ),
      const SizedBox(height: 30),
    ]);
  }

  Widget _pollView(List<Map> options) {
    final sample = (poll?["sample"] as num?)?.toInt() ?? 0;
    final spread = (poll?["spread"] as Map?) ?? {};
    if (sample == 0) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text("The class has never faced this question. You are the pioneer 🫡",
            textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9FB0CC), fontSize: 11)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
          children: options.map((o) {
            final k = "${o["key"]}";
            final v = (spread[k] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 26, height: 6 + v,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0xFF3EA0EE))),
                const SizedBox(height: 3),
                Text("$k · ${v.round()}%", style: const TextStyle(color: Color(0xFFB9C6E8), fontSize: 9)),
              ]),
            );
          }).toList()),
        Text("real answers from $sample Belloxdydx attempt${sample == 1 ? "" : "s"}",
            style: const TextStyle(color: Color(0xFF7C8CA8), fontSize: 9)),
      ]),
    );
  }

  Widget _life(String label, bool used, VoidCallback fn) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: used ? const Color(0xFF5E6E8C) : Colors.white,
        side: BorderSide(color: used ? const Color(0x33FFFFFF) : const Color(0xFFD4AF37)),
      ),
      onPressed: used || phase != "idle" ? null : fn,
      child: Text(label, style: TextStyle(fontSize: 11, decoration: used ? TextDecoration.lineThrough : null)),
    );
  }

  Widget _hex({required Widget child, required String state}) {
    Color a, b;
    switch (state) {
      case "right": a = const Color(0xFF15803D); b = const Color(0xFF22C55E); break;
      case "wrong": a = const Color(0xFF991B1B); b = const Color(0xFFEF4444); break;
      case "picked": a = const Color(0xFFB45309); b = const Color(0xFFF59E0B); break;
      default: a = const Color(0xFF0E1440); b = const Color(0xFF1C2766);
    }
    return Opacity(
      opacity: state == "dead" ? 0.25 : 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(colors: [a, b, a]),
          border: Border.all(color: state == "idle" || state == "dead" ? const Color(0xFFD4AF37) : Colors.white, width: 1.6),
          boxShadow: state == "picked"
              ? [const BoxShadow(color: Color(0x88F59E0B), blurRadius: 22)]
              : state == "right"
                  ? [const BoxShadow(color: Color(0x8022C55E), blurRadius: 22)]
                  : null,
        ),
        child: child,
      ),
    );
  }

  Widget _overView(Color gold) {
    final o = over!;
    final crowned = o["crowned"] == true;
    final timeUp = o["timeUp"] == true;
    final fell = o["fell"] == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(crowned ? "👑" : timeUp ? "⏱" : fell ? "💥" : "🚶", style: const TextStyle(fontSize: 60)),
          const SizedBox(height: 8),
          Text(
            crowned
                ? "BELLOXDYDX MILLIONAIRE!"
                : timeUp
                    ? "TIME! The clock showed no mercy."
                    : fell
                        ? "The stage got you…"
                        : "You walked with the money.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Text(_fmt((o["won"] as num).toInt()),
              style: TextStyle(color: gold, fontSize: 42, fontWeight: FontWeight.w900)),
          const Text("bragging money · recorded in the Hall of Winners",
              style: TextStyle(color: Color(0xFF7C8CA8), fontSize: 11)),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: const Color(0xFF0B1220)),
            onPressed: () => setState(() { qs = null; over = null; }),
            child: const Text("Play again"),
          ),
        ]),
      ),
    );
  }
}
