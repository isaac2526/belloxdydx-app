import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// THE COLD ROOM
///
/// An account on hold is a conversation, not a punishment. This screen
/// says who it is about, what the admin actually wrote, and gives the
/// one action that ends it. Nothing is deleted and nothing is lost —
/// and the student is told so in the first breath.
/// ============================================================

class FrozenScreen extends ConsumerStatefulWidget {
  const FrozenScreen({super.key});

  @override
  ConsumerState<FrozenScreen> createState() => _FrozenScreenState();
}

class _FrozenScreenState extends ConsumerState<FrozenScreen> {
  bool _signingOut = false;

  Future<void> _openChat(String username) async {
    try {
      final opened = await launchUrl(
        Uri.parse(BxConfig.waFrozen(username)),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        bxToast(context, 'WhatsApp would not open on this phone.', error: true);
      }
    } catch (_) {
      if (mounted) {
        bxToast(context, 'WhatsApp would not open on this phone.', error: true);
      }
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await ref.read(sessionProvider.notifier).signOut();
    // The router carries the student back to the door on its own.
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final profile = ref.watch(profileProvider);
    final name = profile.firstName.isEmpty ? 'there' : profile.firstName;
    final reason = profile.frozenReason.trim();

    return Scaffold(
      body: SafeArea(
        child: BxPage(
          padding: const EdgeInsets.fromLTRB(
              BxSpace.lg, BxSpace.xxl, BxSpace.lg, BxSpace.xl),
          child: BxStagger(
            spacing: BxSpace.lg,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.infoTint,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.info.withValues(alpha: 0.34)),
                    ),
                    child: Icon(Icons.ac_unit_rounded, size: 27, color: c.info),
                  ),
                  const SizedBox(height: BxSpace.md),
                  const BxEyebrow('Account on hold'),
                  const SizedBox(height: BxSpace.xxs),
                  Text('Hold on a moment, $name.', style: BxType.h1(c.ink)),
                  const SizedBox(height: BxSpace.xs),
                  Text(
                    'Tutor Bello has paused this account for now. Nothing is '
                    'deleted — your streak, your results, your bookmarks and '
                    'your vault are all exactly where you left them, waiting '
                    'for this to be sorted.',
                    style: BxType.bodyLg(c.inkSoft),
                  ),
                ],
              ),
              if (reason.isNotEmpty)
                BxCard(
                  accent: BxAccent.info,
                  padding: const EdgeInsets.all(BxSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BxEyebrow('The reason given'),
                      const SizedBox(height: BxSpace.xs),
                      Text(reason, style: BxType.body(c.ink)),
                    ],
                  ),
                ),
              BxCard(
                padding: const EdgeInsets.all(BxSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BxKeyValue('Account', profile.handle),
                    if (profile.fullName.isNotEmpty)
                      BxKeyValue('Name', profile.fullName),
                    const SizedBox(height: BxSpace.sm),
                    Text(
                      'Send one message and it usually clears the same day. '
                      'Your username is already in the message.',
                      style: BxType.small(c.muted),
                    ),
                    const SizedBox(height: BxSpace.md),
                    BxButton(
                      'Chat Tutor Bello',
                      icon: Icons.chat_bubble_outline_rounded,
                      large: true,
                      expand: true,
                      onPressed: () => _openChat(profile.username),
                    ),
                  ],
                ),
              ),
              Center(
                child: BxButton.ghost(
                  'Sign out',
                  icon: Icons.logout_rounded,
                  loading: _signingOut,
                  loadingLabel: 'Signing out…',
                  onPressed: _signOut,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
