import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// A gentle, non blocking Update popup. When the website reports a
// newer build, this offers a one tap link to the fresh APK. Students
// can dismiss it and keep working; nagging is not our style.
void showUpdateDialog(BuildContext context, Map<String, dynamic> info) {
  final notes = "${info["notes"] ?? ""}";
  final url = "${info["apkUrl"] ?? ""}";
  final name = "${info["versionName"] ?? ""}";
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text("Update available${name.isNotEmpty ? "  ·  v$name" : ""}"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("A newer version of Belloxdydx is ready."),
          if (notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(notes,
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Later"),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            if (url.startsWith("http")) {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: const Text("Update now"),
        ),
      ],
    ),
  );
}
