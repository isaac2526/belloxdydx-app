import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../config.dart';
import '../biometric.dart';
import 'shell.dart';
import 'activate.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  String? error;
  String? frozen;

  Future<void> _submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      frozen = null;
    });
    try {
      final activated = await Api.login(email.text, pass.text);
      await Api.fetchContent();

      // Offer biometric enrollment once, after a successful password login.
      if (await Biometric.available() && !(await Biometric.isEnabled())) {
        if (mounted) await _offerBiometric();
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => activated ? const ShellScreen() : const ActivateScreen()));
    } on FrozenException catch (e) {
      setState(() {
        frozen = e.reason ?? "Your account is frozen. Contact Tutor Bello.";
        busy = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        busy = false;
      });
    }
  }

  Future<void> _offerBiometric() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("🔐 Lock the app with your fingerprint?"),
        content: const Text(
          "Next time, open Belloxdydx with your fingerprint or face instead of typing your password. Your data never leaves your phone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Not now")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Turn on")),
        ],
      ),
    );
    if (yes == true) {
      final ok = await Biometric.prompt("Confirm to turn on fingerprint unlock");
      if (ok) await Biometric.setEnabled(true);
    }
  }

  Future<void> _whatsapp(String text) async {
    await launchUrl(Uri.parse("https://wa.me/?text=$text"),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 30),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset("assets/logo.png", width: 84, height: 84),
              ),
            ),
            const SizedBox(height: 14),
            Center(
                child: Text("Welcome back",
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 26, fontWeight: FontWeight.w800))),
            const SizedBox(height: 28),
            if (frozen != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("❄️ Your account is frozen",
                          style: TextStyle(
                              color: Colors.redAccent, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(frozen!, style: TextStyle(color: hint)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => _whatsapp(
                            "Hi Tutor Bello, my account is frozen. My username is "),
                        child: const Text("Appeal to Tutor Bello"),
                      ),
                    ],
                  ),
                ),
              ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: "Email or username"),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 10),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: busy ? null : _submit,
              child: busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Log in"),
            ),
            const SizedBox(height: 12),
            Center(
                child: Text("New here? Create your account on the website.",
                    style: TextStyle(color: hint, fontSize: 12))),
            const SizedBox(height: 40),
            Center(
                child: Text(brandFooter,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: hint, fontSize: 11))),
          ],
        ),
      ),
    );
  }
}
