import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// FORGOT PASSWORD
///
/// Two ways home, said plainly. The email route is first because it is
/// instant; the WhatsApp route is there because plenty of students
/// registered with an address they have never opened since.
/// ============================================================

class ForgotScreen extends ConsumerStatefulWidget {
  const ForgotScreen({super.key});

  @override
  ConsumerState<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends ConsumerState<ForgotScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email)) {
      setState(() => _error = 'Enter the email address you registered with.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authRepoProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } on BxError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send it. Check your connection and try again.';
      });
    }
  }

  void _backToLogin() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      context.go(Routes.login);
    }
  }

  Future<void> _openChat() async {
    try {
      final opened = await launchUrl(
        Uri.parse(BxConfig.waPasswordReset('')),
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

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    return Scaffold(
      appBar: const BxAppBar(
        title: 'Forgot password',
        subtitle: 'We will get you back in',
      ),
      body: BxPage(
        child: BxSwitcher(
          child: _sent ? _sentPanel(c) : _formPanel(c),
        ),
      ),
    );
  }

  // ---- before sending ----
  Widget _formPanel(BxColors c) {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BxEyebrow('Route one · Email'),
        const SizedBox(height: BxSpace.xs),
        Text('Send me a reset link', style: BxType.h2(c.ink)),
        const SizedBox(height: BxSpace.xxs),
        Text(
          'Type the email you registered with. We send a link that opens '
          'straight back in this app, where you pick a new password.',
          style: BxType.body(c.inkSoft),
        ),
        const SizedBox(height: BxSpace.lg),
        BxCard(
          padding: const EdgeInsets.all(BxSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BxField(
                label: 'Email',
                controller: _email,
                hint: 'you@mail.com',
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHint: AutofillHints.email,
                error: _error,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: BxSpace.md),
              BxButton(
                'Send reset link',
                large: true,
                expand: true,
                loading: _busy,
                loadingLabel: 'Sending…',
                onPressed: _send,
              ),
            ],
          ),
        ),
        const SizedBox(height: BxSpace.xl),
        _whatsappCard(c),
        const SizedBox(height: BxSpace.lg),
        Center(
          child: TextButton(
            onPressed: _backToLogin,
            child: const Text('Back to log in'),
          ),
        ),
      ],
    );
  }

  // ---- after sending: a state, not a toast ----
  Widget _sentPanel(BxColors c) {
    return Column(
      key: const ValueKey('sent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BxCard(
          accent: BxAccent.success,
          padding: const EdgeInsets.all(BxSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.success.withValues(alpha: 0.36)),
                ),
                child: Icon(Icons.mark_email_read_rounded,
                    size: 23, color: c.success),
              ),
              const SizedBox(height: BxSpace.md),
              Text('Check your inbox', style: BxType.h2(c.ink)),
              const SizedBox(height: BxSpace.xxs),
              Text(
                'A reset link is on its way to ${_email.text.trim()}. '
                'Open it on this phone and it drops you back here to set a '
                'new password.',
                style: BxType.body(c.inkSoft),
              ),
              const SizedBox(height: BxSpace.md),
              const BxDivider(height: BxSpace.xs),
              const SizedBox(height: BxSpace.sm),
              const _Tip(text: 'It can take a minute or two to arrive.'),
              const _Tip(text: 'Not there? Look in Spam or Promotions.'),
              const _Tip(
                  text: 'The link works once, and only for a short while.'),
              const SizedBox(height: BxSpace.md),
              Row(
                children: [
                  Expanded(
                    child: BxButton.secondary(
                      'Use another email',
                      icon: Icons.edit_outlined,
                      expand: true,
                      onPressed: () => setState(() => _sent = false),
                    ),
                  ),
                  const SizedBox(width: BxSpace.sm),
                  Expanded(
                    child: BxButton(
                      'Back to log in',
                      expand: true,
                      onPressed: _backToLogin,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: BxSpace.xl),
        _whatsappCard(c),
      ],
    );
  }

  Widget _whatsappCard(BxColors c) {
    return BxCard(
      accent: BxAccent.gold,
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BxEyebrow('Route two · WhatsApp'),
          const SizedBox(height: BxSpace.xs),
          Text('No email? That is common', style: BxType.h3(c.ink)),
          const SizedBox(height: BxSpace.xxs),
          Text(
            'Plenty of students registered with an address they never open. '
            'If the link never lands, message Tutor Bello with your username '
            'and he resets it by hand — usually the same day.',
            style: BxType.small(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.md),
          BxButton.secondary(
            'Chat Tutor Bello',
            icon: Icons.chat_bubble_outline_rounded,
            expand: true,
            onPressed: _openChat,
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Padding(
      padding: const EdgeInsets.only(bottom: BxSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 5, color: c.muted),
          ),
          const SizedBox(width: BxSpace.xs),
          Expanded(child: Text(text, style: BxType.small(c.muted))),
        ],
      ),
    );
  }
}
