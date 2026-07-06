import 'package:flutter/material.dart';
import 'viewer.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await VaultIndex.list();
    if (mounted) setState(() => items = list);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: items.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  "Your offline vault is empty.\n\nOpen any note or slide and tap the ⬇ download icon. It saves INSIDE the app only, readable with zero network, invisible to file managers.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70)),
            ))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text("Offline vault",
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text("Reads with no network. Lives only inside the app.",
                    style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 14),
                ...items.map((e) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ViewerScreen(
                                    materialId: "${e["id"]}",
                                    title: "${e["title"]}",
                                    type: "${e["type"]}",
                                    offline: true,
                                  )));
                          _load();
                        },
                        leading: const Icon(Icons.download_done,
                            color: Color(0xFFF5B301)),
                        title: Text("${e["title"]}",
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await VaultIndex.remove("${e["id"]}");
                            _load();
                          },
                        ),
                      ),
                    )),
              ],
            ),
    );
  }
}
