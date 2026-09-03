import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// ACTIVATION
///
/// The one screen where money changes hands, so it is the one screen
/// that has to be unambiguous: four steps, one account number that can
/// be copied without squinting, one WhatsApp button, one key field.
///
/// It is also the only surface in the app allowed a rich fill — the
/// payment card is inverted ink so the account number reads like an
/// engraved plate rather than another form row.
/// ============================================================

class ActivateScreen extends ConsumerStatefulWidget {
  const ActivateScreen({super.key});

  @override
  ConsumerState<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends ConsumerState<ActivateScreen> {
  final _key = TextEditingController();

  bool _busy = false;
  bool _opened = false;
  String? _error;
  Timer? _finish;

  static const _digits = 9;

  @override
  void dispose() {
    _finish?.cancel();
    _key.dispose();
    super.dispose();
  }

  int get _typed => _key.text.trim().length;

  Future<void> _activate() async {
    if (_busy || _typed != _digits) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final router = GoRouter.of(context);

    try {
      await ref.read(authRepoProvider).activate(_key.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _opened = true;
      });
      // Let the student see it land before the app moves.
      _finish = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        ref.read(sessionProvider.notifier).markActivated();
        router.go(Routes.home);
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
        _error =
            'That did not go through. Check your connection and try again.';
      });
    }
  }

  Future<void> _copy(String value, String said) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    bxToast(context, said);
  }

  Future<void> _openChat(String url) async {
    try {
      final opened =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
    final profile = ref.watch(profileProvider);
    final wide = context.isMedium;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _steps(c),
        const SizedBox(height: BxSpace.md),
        _paymentCard(c),
        const SizedBox(height: BxSpace.md),
        BxButton(
          'Send proof on WhatsApp',
          icon: Icons.chat_bubble_outline_rounded,
          large: true,
          expand: true,
          onPressed: () => _openChat(
              BxConfig.waActivation(profile.fullName, profile.username)),
        ),
        const SizedBox(height: BxSpace.xs),
        Text(
          'It opens a message already written, with your name and username '
          'in it. Attach the receipt and send.',
          textAlign: TextAlign.center,
          style: BxType.tiny(c.muted),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BxSwitcher(
          child: profile.isActivated && !_opened
              ? _alreadyPanel(c)
              : _opened
                  ? _successPanel(c)
                  : _keyPanel(c),
        ),
        const SizedBox(height: BxSpace.md),
        _rules(c),
        const SizedBox(height: BxSpace.md),
        BxButton.ghost(
          _opened ? 'Go to my dashboard' : 'Do this later',
          expand: true,
          onPressed: () => context.go(Routes.home),
        ),
        Text(
          'Preview mode stays open. You can look around the whole app and '
          'come back to this screen from anywhere.',
          textAlign: TextAlign.center,
          style: BxType.tiny(c.muted),
        ),
      ],
    );

    return Scaffold(
      appBar: BxAppBar(
        title: 'Activate your account',
        subtitle: profile.username.isEmpty ? null : profile.handle,
      ),
      body: BxPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _intro(c, profile),
            const SizedBox(height: BxSpace.lg),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: BxSpace.md),
                  Expanded(child: right),
                ],
              )
            else ...[
              left,
              const SizedBox(height: BxSpace.xl),
              right,
            ],
          ],
        ),
      ),
    );
  }

  // ---- the promise, in one paragraph ----
  Widget _intro(BxColors c, Profile profile) {
    final name = profile.firstName.isEmpty ? 'there' : profile.firstName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BxEyebrow('One key · One session · Everything'),
        const SizedBox(height: BxSpace.xs),
        Text('One key opens the whole of 100 level, $name.',
            style: BxType.h2(c.ink)),
        const SizedBox(height: BxSpace.xxs),
        Text(
          'Every note, slide, video, past question, CBT test and exam '
          'simulation for both semesters. Pay once and it stays open — '
          'no monthly anything.',
          style: BxType.body(c.inkSoft),
        ),
      ],
    );
  }

  // ---- four steps ----
  Widget _steps(BxColors c) {
    const steps = <List<String>>[
      [
        'Pay ₦3,000',
        'Transfer to the account below from any bank app. One payment, no renewal.',
      ],
      [
        'Send proof',
        'Screenshot the receipt and send it to Tutor Bello on WhatsApp with your username.',
      ],
      [
        'Receive your key',
        'He sends back a 9-digit key made for your account and nobody else’s.',
      ],
      [
        'Enter it here',
        'Type the 9 digits in the panel and the whole app opens at once.',
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: BxSpace.xs),
          BxCard(
            padding: const EdgeInsets.symmetric(
                horizontal: BxSpace.md, vertical: BxSpace.sm + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.goldTint,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.gold.withValues(alpha: 0.42)),
                  ),
                  child: Text('${i + 1}',
                      style: BxType.mono(c.goldDeep, size: 12.5, weight: 600)),
                ),
                const SizedBox(width: BxSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(steps[i][0], style: BxType.bodyStrong(c.ink)),
                      const SizedBox(height: 1),
                      Text(steps[i][1], style: BxType.small(c.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---- the payment plate: inverted ink, the one rich surface ----
  Widget _paymentCard(BxColors c) {
    final on = c.ground; // ink's opposite in both themes
    final soft = on.withValues(alpha: 0.66);
    final amount = NumberFormat.decimalPattern().format(BxConfig.priceNgn);

    return BxCard(
      fill: c.ink,
      border: c.ink,
      raised: true,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BxEyebrow('Pay into', color: soft),
              Icon(Icons.verified_rounded, size: 17, color: soft),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          Text(BxConfig.paymentBank, style: BxType.h2(on)),
          const SizedBox(height: BxSpace.md),
          BxEyebrow('Account number', color: soft),
          const SizedBox(height: BxSpace.xxs),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    BxConfig.paymentAccount,
                    style: BxType.mono(on, size: 27, weight: 600)
                        .copyWith(letterSpacing: 3.4),
                  ),
                ),
              ),
              const SizedBox(width: BxSpace.xs),
              _CopyButton(
                on: on,
                onTap: () =>
                    _copy(BxConfig.paymentAccount, 'Account number copied'),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.md),
          BxEyebrow('Account name', color: soft),
          const SizedBox(height: BxSpace.xxs),
          Text(BxConfig.paymentName, style: BxType.bodyStrong(on)),
          const SizedBox(height: BxSpace.md),
          Container(height: 1, color: on.withValues(alpha: 0.16)),
          const SizedBox(height: BxSpace.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BxEyebrow('Amount', color: soft),
                    const SizedBox(height: BxSpace.xxs),
                    Text('₦$amount', style: BxType.figure(on)),
                  ],
                ),
              ),
              _CopyButton(
                on: on,
                label: 'Copy amount',
                onTap: () => _copy('${BxConfig.priceNgn}', 'Amount copied'),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.sm),
          Text(
            'Send the exact amount so your receipt matches your name on the '
            'list.',
            style: BxType.tiny(soft),
          ),
        ],
      ),
    );
  }

  // ---- the key panel ----
  Widget _keyPanel(BxColors c) {
    final ready = _typed == _digits;

    return BxCard(
      key: const ValueKey('key'),
      accent: BxAccent.gold,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BxEyebrow('Have your key?'),
          const SizedBox(height: BxSpace.xs),
          Text('Enter the 9 digits', style: BxType.h2(c.ink)),
          const SizedBox(height: BxSpace.xxs),
          Text(
            'The key Tutor Bello sent you works on this account only. '
            'No spaces, no dashes — just the numbers.',
            style: BxType.small(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.lg),
          BxField(
            label: 'Activation key',
            controller: _key,
            hint: '· · · · · · · · ·',
            enabled: !_busy,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: _digits,
            style: BxType.mono(c.ink, size: 24, weight: 600)
                .copyWith(letterSpacing: 5),
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_digits),
            ],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _activate(),
          ),
          const SizedBox(height: BxSpace.sm),
          Row(
            children: [
              Expanded(
                child: BxProgressBar(
                  _typed / _digits,
                  color: ready ? c.success : c.gold,
                  height: 5,
                ),
              ),
              const SizedBox(width: BxSpace.sm),
              Text('$_typed/$_digits',
                  style: BxType.mono(ready ? c.success : c.muted, size: 12)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: BxSpace.md),
            BxBanner(
              title: 'That key did not work',
              message: _error!,
              icon: Icons.key_off_rounded,
              accent: BxAccent.danger,
              actionLabel: 'Chat Tutor Bello',
              onAction: () => _openChat(BxConfig.waHelp('my activation key')),
            ),
          ],
          const SizedBox(height: BxSpace.md),
          BxButton(
            'Activate my account',
            large: true,
            expand: true,
            loading: _busy,
            loadingLabel: 'Opening everything…',
            onPressed: ready ? _activate : null,
          ),
          if (!ready) ...[
            const SizedBox(height: BxSpace.xs),
            Text(
              _typed == 0
                  ? 'No key yet? Do the four steps first.'
                  : '${_digits - _typed} more ${_digits - _typed == 1 ? 'digit' : 'digits'} to go.',
              textAlign: TextAlign.center,
              style: BxType.tiny(c.muted),
            ),
          ],
        ],
      ),
    );
  }

  // ---- it worked ----
  Widget _successPanel(BxColors c) {
    return BxCard(
      key: const ValueKey('done'),
      accent: BxAccent.success,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.success.withValues(alpha: 0.4)),
              ),
              child: Icon(Icons.check_rounded, size: 30, color: c.success),
            ),
          ),
          const SizedBox(height: BxSpace.md),
          Text('You are in.',
              textAlign: TextAlign.center, style: BxType.h1(c.ink)),
          const SizedBox(height: BxSpace.xxs),
          Text(
            'Every note, video, past question and test for 100 level just '
            'opened. Start with one topic today.',
            textAlign: TextAlign.center,
            style: BxType.body(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.md),
          Text('Taking you to your dashboard…',
              textAlign: TextAlign.center, style: BxType.tiny(c.muted)),
        ],
      ),
    );
  }

  // ---- already activated: nothing to buy twice ----
  Widget _alreadyPanel(BxColors c) {
    return BxCard(
      key: const ValueKey('already'),
      accent: BxAccent.success,
      padding: const EdgeInsets.all(BxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, size: 21, color: c.success),
              const SizedBox(width: BxSpace.xs),
              Expanded(
                child: Text('This account is already active',
                    style: BxType.h3(c.ink)),
              ),
            ],
          ),
          const SizedBox(height: BxSpace.xs),
          Text(
            'Nothing more to pay. Everything for 100 level is open on this '
            'account right now.',
            style: BxType.small(c.inkSoft),
          ),
          const SizedBox(height: BxSpace.md),
          BxButton(
            'Go to my dashboard',
            expand: true,
            onPressed: () => context.go(Routes.home),
          ),
        ],
      ),
    );
  }

  // ---- the rules, said once, plainly ----
  Widget _rules(BxColors c) {
    return BxCard(
      padding: const EdgeInsets.all(BxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BxEyebrow('Good to know'),
          const SizedBox(height: BxSpace.sm),
          const _Rule(
            icon: Icons.vpn_key_rounded,
            text: 'A key works once. Once it opens your account it is spent, '
                'so never pass it on.',
          ),
          const _Rule(
            icon: Icons.phonelink_lock_rounded,
            text: 'Your account locks to this phone. Changed device? Chat '
                'Tutor Bello and he moves it.',
          ),
          const _Rule(
            icon: Icons.person_pin_circle_rounded,
            text: 'One live login at a time. Signing in somewhere else closes '
                'this one.',
          ),
        ],
      ),
    );
  }
}

/// The small inverted copy control used on the payment plate.
class _CopyButton extends StatelessWidget {
  final Color on;
  final String label;
  final VoidCallback onTap;

  const _CopyButton(
      {required this.on, required this.onTap, this.label = 'Copy'});

  @override
  Widget build(BuildContext context) {
    return BxScaleTap(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: BxSpace.sm, vertical: BxSpace.xs),
        decoration: BoxDecoration(
          color: on.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(BxRadius.sm),
          border: Border.all(color: on.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_rounded, size: 14, color: on),
            const SizedBox(width: 5),
            Text(label, style: BxType.smallStrong(on)),
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Rule({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Padding(
      padding: const EdgeInsets.only(bottom: BxSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.muted),
          const SizedBox(width: BxSpace.xs),
          Expanded(child: Text(text, style: BxType.small(c.inkSoft))),
        ],
      ),
    );
  }
}
