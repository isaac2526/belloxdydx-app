import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';

// A slim, honest status strip. Green when the line is sharp, amber when
// it is dragging, red when the phone is offline. It checks quietly every
// few seconds and never blocks anything.
class ConnectionBar extends StatefulWidget {
  const ConnectionBar({super.key});
  @override
  State<ConnectionBar> createState() => _ConnectionBarState();
}

class _ConnectionBarState extends State<ConnectionBar> {
  Timer? _timer;
  int ms = 0; // 0 = checking, -1 = offline, >0 = latency
  bool checking = true;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  Future<void> _check() async {
    final r = await Api.ping();
    if (mounted) {
      setState(() {
        ms = r;
        checking = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3ECF8E);
    const amber = Color(0xFFF5B301);
    const red = Color(0xFFFF5A67);

    Color color;
    String label;
    IconData icon;
    int bars;

    if (checking) {
      color = amber;
      label = "Checking your connection";
      icon = Icons.wifi_find;
      bars = 1;
    } else if (ms < 0) {
      color = red;
      label = "No internet connection";
      icon = Icons.wifi_off;
      bars = 0;
    } else if (ms < 700) {
      color = green;
      label = "Online · strong";
      icon = Icons.wifi;
      bars = 3;
    } else if (ms < 2000) {
      color = green;
      label = "Online · fair";
      icon = Icons.wifi_2_bar;
      bars = 2;
    } else {
      color = amber;
      label = "Online · slow";
      icon = Icons.wifi_1_bar;
      bars = 1;
    }

    return Material(
      color: color.withOpacity(0.13),
      child: InkWell(
        onTap: _check, // tap the strip to test again right now
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const Spacer(),
                ...List.generate(3, (i) {
                  return Container(
                    margin: const EdgeInsets.only(left: 2),
                    width: 3,
                    height: 5.0 + i * 3,
                    decoration: BoxDecoration(
                      color: i < bars ? color : color.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                if (ms > 0)
                  Text("${ms}ms",
                      style: TextStyle(
                          fontSize: 10,
                          color: color.withOpacity(0.85),
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
