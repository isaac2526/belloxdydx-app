import 'package:flutter/material.dart';
import '../api.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  @override
  Widget build(BuildContext context) {
    final list =
        ((Api.content?["announcements"] as List?) ?? []).cast<Map>();
    return SafeArea(
      child: list.isEmpty
          ? const Center(child: Text("No announcements yet."))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text("Announcements",
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                ...list.map((a) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () async {
                          await showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                    title: Text("${a["title"]}"),
                                    content: SingleChildScrollView(
                                        child: Text("${a["body"]}")),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text("I've seen it ✓")),
                                    ],
                                  ));
                          if (a["unread"] == true) {
                            await Api.ack("${a["id"]}");
                            setState(() => a["unread"] = false);
                          }
                        },
                        leading: Icon(Icons.campaign,
                            color: a["unread"] == true
                                ? const Color(0xFFF5B301)
                                : Colors.white38),
                        title: Text("${a["title"]}",
                            style: TextStyle(
                                fontWeight: a["unread"] == true
                                    ? FontWeight.w800
                                    : FontWeight.w500)),
                        subtitle: Text("${a["body"]}",
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: a["unread"] == true
                            ? const CircleAvatar(
                                radius: 5,
                                backgroundColor: Color(0xFFF5B301))
                            : null,
                      ),
                    )),
              ],
            ),
    );
  }
}
