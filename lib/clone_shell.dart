import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';

// ============================================================
// THE EXACT CLONE
// The app IS the website — the same landing, menus, colours,
// Millionaire, practice, tests, activation, everything — wrapped
// in native glass:
//   · the session lives in the shell's cookies, so one login
//     lasts; no more "create account / login" every open
//   · FLAG_SECURE stays: screenshots come out black
//   · offline shows a branded retry page (never a raw URL)
//   · wa.me / tel / external links open outside properly
//   · the Android back button walks history like a browser
// And the superpower: edit the website, and every installed app
// updates INSTANTLY — no APK release needed.
// ============================================================

class CloneShell extends StatefulWidget {
  const CloneShell({super.key});
  @override
  State<CloneShell> createState() => _CloneShellState();
}

class _CloneShellState extends State<CloneShell> {
  late final WebViewController controller;
  bool booting = true;
  bool failed = false;
  int progress = 0;

  static const _home = baseUrl; // https://www.belloxdydx.org

  bool _ours(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    final h = u.host;
    return h.endsWith("belloxdydx.org") ||
        h.endsWith("vercel.app") ||
        h.contains("supabase.co") ||
        h.contains("officeapps.live.com") ||
        h.contains("docs.google.com");
  }

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setUserAgent(
          "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36 BelloxdydxApp/$appVersionCode")
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => progress = p),
        onPageStarted: (_) => setState(() => failed = false),
        onPageFinished: (_) => setState(() => booting = false),
        onWebResourceError: (e) {
          // Only a MAIN-frame failure means the page truly died.
          if (e.isForMainFrame ?? true) {
            setState(() {
              failed = true;
              booting = false;
            });
          }
        },
        onNavigationRequest: (req) {
          final url = req.url;
          if (_ours(url)) return NavigationDecision.navigate;
          // WhatsApp, tel, mail, and the outside world open outside.
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(_home));
  }

  Future<bool> _back() async {
    if (await controller.canGoBack()) {
      controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _back() && context.mounted) {
          // At the true root: let Android minimise instead of killing.
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(children: [
            WebViewWidget(controller: controller),
            if (progress > 0 && progress < 100)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 2.5,
                  color: const Color(0xFFF5B301),
                  backgroundColor: Colors.transparent,
                ),
              ),
            if (booting) _splash(),
            if (failed) _offline(),
          ]),
        ),
      ),
    );
  }

  Widget _splash() => Container(
        color: const Color(0xFF0B1220),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                  colors: [Color(0xFFF5B301), Color(0xFFFF7A00)]),
              boxShadow: const [
                BoxShadow(color: Color(0x66F5B301), blurRadius: 30)
              ],
            ),
            child: const Text("B",
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          const SizedBox(height: 18),
          const Text("Belloxdydx",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text("Loading your campus…",
              style: TextStyle(color: Color(0xFF9FB0CC), fontSize: 12)),
          const SizedBox(height: 26),
          // Mature loader: a thin gold hairline that fills with the real
          // page progress, and a quiet percentage — no game-style bars.
          SizedBox(
            width: 150,
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress / 100 : null,
                  minHeight: 2,
                  color: const Color(0xFFF5B301),
                  backgroundColor: const Color(0xFF1C2766),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                progress > 0 ? "$progress%" : "",
                style: const TextStyle(
                    color: Color(0xFF7C8CA8),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ]),
          ),
        ]),
      );

  Widget _offline() => Container(
        color: const Color(0xFF0B1220),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("📡", style: TextStyle(fontSize: 46)),
          const SizedBox(height: 10),
          const Text("Network wobbled",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            "We could not reach Belloxdydx. Check your data or Wi-Fi and try again — your session is safe.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9FB0CC), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF5B301),
                foregroundColor: const Color(0xFF0B1220),
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 14)),
            onPressed: () {
              setState(() {
                failed = false;
                booting = true;
              });
              controller.reload();
            },
            child: const Text("Retry",
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}
