import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// A gentle, non blocking Update popup. When the website reports a
// newer build, this offers a one tap link to the fresh APK. Students
// can dismiss it and keep working; nagging is not our style.
void showUpdateDialog(BuildContext context, Map<String, dynamic> info,
    {bool required = false}) {
  final notes = "${info["notes"] ?? ""}";
  final url = "${info["apkUrl"] ?? ""}";
  final name = "${info["versionName"] ?? ""}";
  showDialog(
    context: context,
    // A required update cannot be waved away.
    barrierDismissible: !required,
    builder: (_) => PopScope(
      canPop: !required,
      child: AlertDialog(
      title: Text((required ? "Update required" : "Update available") +
          (name.isNotEmpty ? "  ·  v$name" : "")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(required
              ? "This version of Belloxdydx is no longer supported. Update to keep studying."
              : "A newer version of Belloxdydx is ready."),
          if (notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(notes,
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ],
      ),
      actions: [
        if (!required)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
        FilledButton(
          onPressed: () {
            if (!required) Navigator.pop(context);
            if (url.startsWith("http")) {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: const Text("Update now"),
        ),
      ],
      ),
    ),
  );
}
