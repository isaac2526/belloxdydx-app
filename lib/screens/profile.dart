import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../config.dart';
import 'login.dart';
import 'activate.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? streak;

  @override
  void initState() {
    super.initState();
    Api.streakTouch().then((j) {
      if (mounted) setState(() => streak = (j["current"] as num?)?.toInt());
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = (Api.content?["me"] as Map?) ?? {};
    final activated = me["is_activated"] == true || Api.activated;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: const Color(0xFFF5B301),
              child: Text(
                  "${(me["first_name"] ?? "B")}".substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      fontSize: 30,
                      color: Color(0xFF0B1220),
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
              child: Text("@${me["username"] ?? ""}",
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800))),
          Center(
              child: Text(
                  "${me["first_name"] ?? ""} ${me["surname"] ?? ""}",
                  style: const TextStyle(color: Colors.white54))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text("🔥 ${streak ?? "…"}",
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const Text("day streak",
                        style: TextStyle(color: Colors.white54)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text(activated ? "✅" : "🔒",
                        style: const TextStyle(fontSize: 22)),
                    Text(activated ? "activated" : "not activated",
                        style: const TextStyle(color: Colors.white54)),
                  ]),
                ),
              ),
            ),
          ]),
          if (!activated) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ActivateScreen())),
              child: const Text("Activate with a key"),
            ),
          ],
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.card_giftcard,
                  color: Color(0xFFF5B301)),
              title: const Text("Your referral code"),
              subtitle: Text("${me["referral_code"] ?? "—"}",
                  style: const TextStyle(
                      fontFamily: "monospace",
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3)),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: "${me["referral_code"] ?? ""}"));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          "Copied. ₦250 + 50 points per coursemate who activates.")));
                },
              ),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () async {
              await Api.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false);
            },
            child: const Text("Log out"),
          ),
          const SizedBox(height: 30),
          const Center(
              child: Text(brandFooter,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11))),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
