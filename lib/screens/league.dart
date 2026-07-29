import 'package:flutter/material.dart';
import '../api.dart';

// ⚔️ The League: weekly points war + the Hall of Winners, same data
// the website shows, resets every 7 days.
class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});
  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final d = await Api.league();
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    const medals = ["🥇", "🥈", "🥉"];
    return Scaffold(
      appBar: AppBar(title: const Text("⚔️ The League")),
      body: RefreshIndicator(
        onRefresh: _load,
        child: error != null
            ? ListView(padding: const EdgeInsets.all(24), children: [
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Center(child: OutlinedButton(onPressed: _load, child: const Text("Retry"))),
              ])
            : data == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(14), children: [
                    if (data!["myRank"] != null)
                      Card(
                        color: const Color(0x22F5B301),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            "Your seat this week: #${data!["myRank"]} · ${data!["myPoints"]} points",
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
                      child: Text("THIS WEEK'S TABLE",
                          style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
                    ),
                    ...((data!["table"] as List?) ?? []).cast<Map>().asMap().entries.map((e) {
                      final idx = e.key;
                      final r = e.value;
                      return Card(
                        child: ListTile(
                          dense: true,
                          leading: Text(idx < 3 ? medals[idx] : "#${idx + 1}",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          title: Text("@${r["username"]}"),
                          trailing: Text("${r["points"]} pts",
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      );
                    }),
                    if (((data!["table"] as List?) ?? []).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          "Silence on the battlefield. Submit any practice or test and claim the empty throne.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Text("🎰 HALL OF WINNERS · MILLIONAIRE",
                          style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
                    ),
                    ...((data!["winners"] as List?) ?? []).cast<Map>().asMap().entries.map((e) {
                      final r = e.value;
                      final won = (r["won"] as num?)?.toInt() ?? 0;
                      return ListTile(
                        dense: true,
                        leading: Text(r["crowned"] == true ? "👑" : "🎖",
                            style: const TextStyle(fontSize: 18)),
                        title: Text("@${r["username"]}"),
                        trailing: Text("₦${won.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+$)"), (m) => "${m[1]},")}"),
                      );
                    }),
                    if (((data!["winners"] as List?) ?? []).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text("The hot seat is still cold. Be the first name on this wall.",
                            textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 30),
                  ]),
      ),
    );
  }
}
