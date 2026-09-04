import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/ui.dart';
import 'auth_brand.dart';

/// ============================================================
/// ONE MOMENT OF CONNECTION
///
/// Freezing an account is Tutor Bello's only sanction, and until this
/// existed it was trivially defeated: turn the data off and keep the
/// whole paid app for ever. Nothing on the phone and nothing on the
/// server could tell, because the phone never had to come back.
///
/// So a paid account that has not been confirmed in three weeks stops
/// here. Three weeks is deliberately long — a student who cannot buy
/// data for three weeks is exactly who this app is for — and what it
/// asks for is one call, not a sync and not a download. Everything they
/// have saved is untouched and they are told so before anything else.
/// ============================================================

class ReconnectScreen extends ConsumerStatefulWidget {
  const ReconnectScreen({super.key});

  @override
  ConsumerState<ReconnectScreen> createState() => _ReconnectScreenState();
}

class _ReconnectScreenState extends ConsumerState<ReconnectScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Try once on arrival. A student who wandered back into signal
    // never sees this screen at all — it clears itself.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await ref.read(sessionProvider.notifier).checkInNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(sessionProvider.notifier).signOut();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final name = ref.watch(profileProvider).firstName;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(BxSpace.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BxAuthBrand(size: 72),
                        const SizedBox(height: BxSpace.lg),
                        Text(
                          name.isEmpty
                              ? 'Come online once'
                              : '$name, come online once',
                          style: BxType.h1(c.ink),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: BxSpace.sm),
                        Text(
                          'Belloxdydx has not been able to reach the server '
                          'in three weeks, so it needs to check your account '
                          'once before you carry on.',
                          style: BxType.body(c.inkSoft),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: BxSpace.xs),
                        Text(
                          'Nothing you saved has been touched. This is one '
                          'small call — not a download and not a sync — so a '
                          'moment of somebody else\'s Wi-Fi is enough.',
                          style: BxType.small(c.muted),
                          textAlign: TextAlign.center,
                        ),
                        if (_failed) ...[
                          const SizedBox(height: BxSpace.md),
                          const BxBanner(
                            title: 'Still no connection',
                            message: 'Turn your data on, or step where the '
                                'network is better, and tap again.',
                            icon: Icons.wifi_off_rounded,
                            accent: BxAccent.warning,
                          ),
                        ],
                        const SizedBox(height: BxSpace.lg),
                        BxButton(
                          'Check now',
                          icon: Icons.wifi_tethering_rounded,
                          loading: _busy,
                          loadingLabel: 'Checking…',
                          expand: true,
                          large: true,
                          onPressed: _busy ? null : _check,
                        ),
                        const SizedBox(height: BxSpace.xs),
                        TextButton(
                          onPressed: _busy ? null : _signOut,
                          child: Text('Sign out instead',
                              style: BxType.small(c.muted)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
