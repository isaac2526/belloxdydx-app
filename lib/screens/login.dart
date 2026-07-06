import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../config.dart';
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
  int? lockedDays;

  Future<void> _submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      lockedDays = null;
    });
    try {
      final activated = await Api.login(email.text, pass.text);
      await Api.fetchContent();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) =>
              activated ? const ShellScreen() : const ActivateScreen()));
    } on DeviceLockedException catch (e) {
      setState(() {
        lockedDays = e.daysLeft;
        busy = false;
      });
    } catch (e) {
      // Show the REAL reason so we never guess in the dark again.
      setState(() {
        error = e.toString().replaceFirst("Exception: ", "");
        busy = false;
      });
    }
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse(
        "https://wa.me/?text=Hi Tutor Bello, I changed my device. Please reset my device lock. My username is ");
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 30),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset("assets/logo.png", width: 84, height: 84),
              ),
            ),
            const SizedBox(height: 14),
            const Center(
                child: Text("Welcome back",
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
            const SizedBox(height: 28),
            if (lockedDays != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("This account is locked to a different device.",
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          "You can move it yourself in $lockedDays day(s), or chat Tutor Bello for an instant reset.",
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _whatsapp,
                          child: const Text("Chat Tutor Bello on WhatsApp")),
                    ],
                  ),
                ),
              ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: "Email"),
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
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Log in"),
            ),
            const SizedBox(height: 12),
            const Center(
                child: Text("New here? Create your account on the website.",
                    style: TextStyle(color: Colors.white54, fontSize: 12))),
            const SizedBox(height: 40),
            const Center(
                child: Text(brandFooter,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11))),
          ],
        ),
      ),
    );
  }
}
