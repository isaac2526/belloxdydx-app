import 'package:flutter/material.dart';
import '../api.dart';
import 'shell.dart';

class ActivateScreen extends StatefulWidget {
  const ActivateScreen({super.key});
  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final key9 = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> _go() async {
    setState(() {
      busy = true;
      error = null;
    });
    final ok = await Api.activate(key9.text.trim());
    if (!mounted) return;
    if (ok) {
      await Api.fetchContent();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ShellScreen()));
    } else {
      setState(() {
        error = "That key did not open. Check it and try again.";
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Activate your account")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                "Enter your 9 digit activation key. The phone in your hand right now becomes your account's device.",
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 18),
            TextField(
              controller: key9,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Activation key"),
            ),
            const SizedBox(height: 10),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 14),
            FilledButton(
                onPressed: busy ? null : _go, child: const Text("Activate")),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ShellScreen())),
              child: const Text("Skip for now, just look around"),
            ),
          ],
        ),
      ),
    );
  }
}
