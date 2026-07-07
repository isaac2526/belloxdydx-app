import 'package:flutter/material.dart';
import '../api.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.leaderboard();
      if (mounted) setState(() => data = d);
    } catch (_) {
      if (mounted) setState(() => error = "Could not load. Pull to retry.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = (Api.content?["me"] as Map?) ?? {};
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: data == null
            ? ListView(children: [
                const SizedBox(height: 200),
                Center(
                    child: error == null
                        ? const CircularProgressIndicator()
                        : Text(error!)),
              ])
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text("Leaderboard",
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Card(
                    color: Theme.of(context).colorScheme.surface,
                    child: ListTile(
                      leading: const Text("🏅",
                          style: TextStyle(fontSize: 26)),
                      title: Text("You · @${me["username"] ?? ""}",
                          style:
                              const TextStyle(fontWeight: FontWeight.w800)),
                      trailing: Text(
                          "#${(data!["me"] as Map)["rank"]} · ${(data!["me"] as Map)["total"]} pts",
                          style: const TextStyle(
                              color: Color(0xFFF5B301),
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...((data!["top"] as List).cast<Map>()).map((r) => ListTile(
                        dense: true,
                        leading: Text("#${r["rank"]}",
                            style: TextStyle(
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w700)),
                        title: Text("@${r["username"]}"),
                        trailing: Text("${r["total"]} pts",
                            style:
                                const TextStyle(color: Color(0xFFF5B301))),
                      )),
                ],
              ),
      ),
    );
  }
}
