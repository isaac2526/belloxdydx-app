import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _busy = false;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _msgs.add({"role": "user", "text": text});
      _controller.clear();
      _busy = true;
    });
    _toBottom();
    final reply = await Api.aiChat(_msgs);
    if (!mounted) return;
    setState(() {
      _msgs.add({"role": "model", "text": reply});
      _busy = false;
    });
    _toBottom();
  }

  void _toBottom() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gold = const Color(0xFFF5B301);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text("🤖", style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 8),
                Text("Bello AI",
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: _msgs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("🤖", style: const TextStyle(fontSize: 44)),
                          const SizedBox(height: 10),
                          Text("Your 24/7 study tutor",
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                            "Explain a topic, solve a past question step by step, or get a quick summary. Strictly studies, it will dodge gist and LiveScores.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).hintColor),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _msgs.length + (_busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _msgs.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: dark ? Colors.white10 : Colors.black12,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text("Bello AI is thinking…",
                                style: TextStyle(color: Theme.of(context).hintColor)),
                          ),
                        );
                      }
                      final m = _msgs[i];
                      final isUser = m["role"] == "user";
                      return Align(
                        alignment:
                            isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.82),
                          decoration: BoxDecoration(
                            color: isUser
                                ? gold
                                : (dark ? Colors.white10 : Colors.black.withOpacity(0.06)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SelectableText(
                            m["text"] ?? "",
                            style: TextStyle(
                              color: isUser ? const Color(0xFF0B1220) : null,
                              height: 1.35,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              "Bello AI can make mistakes. Confirm important things with your notes.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: "Ask anything academic…",
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: const Icon(Icons.send, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
