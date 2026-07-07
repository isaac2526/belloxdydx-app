import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../security.dart';
import 'home.dart';
import 'vault.dart';
import 'announcements.dart';
import 'leaderboard.dart';
import 'profile.dart';
import 'login.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  int tab = 0;
  Timer? _beat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Security.lockDown();
    Security.watch(() => context);
    _beat = Timer.periodic(const Duration(seconds: 45), (_) => _check());
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!Api.signedIn) return;
    final alive = await Api.heartbeat();
    if (!alive && mounted) {
      await Api.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Signed in on another device. Only one login can be alive.")));
    }
  }

  @override
  void dispose() {
    _beat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const VaultScreen(),
      const AnnouncementsScreen(),
      const LeaderboardScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: "Courses"),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download_done), label: "Offline"),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: "News"),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: "Ranks"),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}
