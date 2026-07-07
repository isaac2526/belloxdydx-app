import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../config.dart';
import '../theme.dart';
import '../biometric.dart';
import 'login.dart';
import 'activate.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? streak;
  bool bioOn = false;
  bool bioAvailable = false;

  @override
  void initState() {
    super.initState();
    Api.streakTouch().then((j) {
      if (mounted) setState(() => streak = (j["current"] as num?)?.toInt());
    });
    _loadBio();
  }

  Future<void> _loadBio() async {
    final avail = await Biometric.available();
    final on = await Biometric.isEnabled();
    if (mounted) setState(() {
      bioAvailable = avail;
      bioOn = on;
    });
  }

  Future<void> _toggleBio(bool v) async {
    if (v) {
      final ok = await Biometric.prompt("Confirm to turn on fingerprint unlock");
      if (!ok) return;
    }
    await Biometric.setEnabled(v);
    setState(() => bioOn = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final me = (Api.content?["me"] as Map?) ?? {};
    final activated = me["is_activated"] == true || Api.activated;
    final gold = const Color(0xFFF5B301);
    final hint = Theme.of(context).hintColor;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: gold,
              child: Text("${(me["first_name"] ?? "B")}".substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 30, color: Color(0xFF0B1220), fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Text("@${me["username"] ?? ""}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          Center(child: Text("${me["first_name"] ?? ""} ${me["surname"] ?? ""}", style: TextStyle(color: hint))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text("🔥 ${streak ?? "…"}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text("day streak", style: TextStyle(color: hint)),
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
                    Text(activated ? "✅" : "🔒", style: const TextStyle(fontSize: 22)),
                    Text(activated ? "activated" : "not activated", style: TextStyle(color: hint)),
                  ]),
                ),
              ),
            ),
          ]),
          if (!activated) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivateScreen())),
              child: const Text("Activate with a key"),
            ),
          ],
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: Icon(Icons.card_giftcard, color: gold),
              title: const Text("Your referral code"),
              subtitle: Text("${me["referral_code"] ?? "—"}",
                  style: const TextStyle(fontFamily: "monospace", fontWeight: FontWeight.w800, letterSpacing: 3)),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: "${me["referral_code"] ?? ""}"));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Copied. ₦250 + 50 points per coursemate who activates.")));
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode, color: gold),
                title: const Text("Dark mode"),
                value: theme.isDark,
                onChanged: (_) => theme.toggle(),
              ),
              if (bioAvailable)
                SwitchListTile(
                  secondary: Icon(Icons.fingerprint, color: gold),
                  title: const Text("Unlock with fingerprint / face"),
                  subtitle: const Text("Ask for your fingerprint when opening the app"),
                  value: bioOn,
                  onChanged: _toggleBio,
                ),
            ]),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () async {
              await Api.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
            },
            child: const Text("Log out"),
          ),
          const SizedBox(height: 30),
          Center(child: Text(brandFooter, textAlign: TextAlign.center, style: TextStyle(color: hint, fontSize: 11))),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
