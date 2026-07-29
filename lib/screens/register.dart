import 'package:flutter/material.dart';
import '../api.dart';

// In-app account creation — the exact same door and details as the
// website, referral code included.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final surname = TextEditingController();
  final firstName = TextEditingController();
  final matric = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final referral = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final err = await Api.register(
        surname: surname.text.trim(),
        firstName: firstName.text.trim(),
        matric: matric.text.trim(),
        email: email.text.trim(),
        phone: phone.text.trim(),
        username: username.text.trim(),
        password: password.text,
        referral: referral.text.trim(),
      );
      if (!mounted) return;
      if (err != null) {
        setState(() => error = err);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Account created! 🎉 Log in with your username and password.")));
        Navigator.of(context).pushReplacementNamed("/login");
      }
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, {String? hint}) => InputDecoration(
        labelText: label, hintText: hint, border: const OutlineInputBorder());
    return Scaffold(
      appBar: AppBar(title: const Text("Create your account")),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            "Same details as the website — one Belloxdydx identity everywhere.",
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(controller: surname, decoration: deco("Surname")),
          const SizedBox(height: 10),
          TextField(controller: firstName, decoration: deco("First name")),
          const SizedBox(height: 10),
          TextField(
              controller: matric,
              decoration: deco("Matric number", hint: "e.g. 236xxx")),
          const SizedBox(height: 10),
          TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: deco("Email")),
          const SizedBox(height: 10),
          TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: deco("Phone (WhatsApp)")),
          const SizedBox(height: 10),
          TextField(
              controller: username,
              decoration:
                  deco("Username", hint: "letters, numbers, _ (3–20)")),
          const SizedBox(height: 10),
          TextField(
              controller: password,
              obscureText: true,
              decoration: deco("Password")),
          const SizedBox(height: 10),
          TextField(
              controller: referral,
              decoration: deco("Referral code (optional)",
                  hint: "Your friend's invite code")),
          const SizedBox(height: 8),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error!,
                  style: const TextStyle(
                      color: Color(0xFFE5484D), fontWeight: FontWeight.w600)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF5B301),
              foregroundColor: const Color(0xFF0B1220),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: busy ? null : _submit,
            child: Text(busy ? "Creating…" : "Create account"),
          ),
        ],
      ),
    );
  }
}
