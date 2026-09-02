import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// SET A NEW PASSWORD
///
/// Where the reset link lands. Same rules as registration, shown the
/// same way — ticking chips, not a paragraph of small print.
/// ============================================================

class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key});

  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  bool _busy = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _ruleLength => _password.text.length >= 8;
  bool get _ruleLetters => RegExp(r'[A-Za-z]').hasMatch(_password.text);
  bool get _ruleSymbols =>
      RegExp(r'[^A-Za-z0-9]').allMatches(_password.text).length >= 2;
  bool get _ruleMatch =>
      _password.text.isNotEmpty && _password.text == _repeat.text;
  bool get _ready => _ruleLength && _ruleLetters && _ruleSymbols && _ruleMatch;

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_ready) return;

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    // Saving may sign the student straight in, which moves the router
    // under our feet — so hold the router, not the context.
    final router = GoRouter.of(context);

    try {
      await ref.read(authRepoProvider).updatePassword(_password.text);
      if (!mounted) return;
      setState(() => _busy = false);
      bxToast(context, 'Password changed. Log in with the new one.');
      router.go(Routes.login);
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
            'Could not save the new password. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;

    return Scaffold(
      appBar: const BxAppBar(
        title: 'New password',
        subtitle: 'Last step of the reset',
      ),
      body: BxPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BxEyebrow('Almost done'),
            const SizedBox(height: BxSpace.xs),
            Text('Choose a new password', style: BxType.h2(c.ink)),
            const SizedBox(height: BxSpace.xxs),
            Text(
              'Pick something you will still remember in exam week — then '
              'log in with it and carry on.',
              style: BxType.body(c.inkSoft),
            ),
            const SizedBox(height: BxSpace.lg),
            if (_error != null) ...[
              BxBanner(
                title: 'Could not change it',
                message: _error!,
                icon: Icons.error_outline_rounded,
                accent: BxAccent.danger,
              ),
              const SizedBox(height: BxSpace.md),
            ],
            BxCard(
              padding: const EdgeInsets.all(BxSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BxPasswordField(
                    label: 'New password',
                    controller: _password,
                    autofillHint: AutofillHints.newPassword,
                    error: _submitted &&
                            !(_ruleLength && _ruleLetters && _ruleSymbols)
                        ? 'At least 8 characters, letters, and 2 symbols.'
                        : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: BxSpace.md),
                  BxPasswordField(
                    label: 'Repeat new password',
                    controller: _repeat,
                    hint: 'Type it once more',
                    autofillHint: AutofillHints.newPassword,
                    error: _submitted && !_ruleMatch
                        ? 'The two passwords do not match yet.'
                        : null,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: BxSpace.md),
                  Wrap(
                    spacing: BxSpace.xs,
                    runSpacing: BxSpace.xs,
                    children: [
                      _RuleChip('8+ characters', _ruleLength),
                      _RuleChip('Letters', _ruleLetters),
                      _RuleChip('2 symbols', _ruleSymbols),
                      _RuleChip('Both match', _ruleMatch),
                    ],
                  ),
                  const SizedBox(height: BxSpace.md),
                  BxButton(
                    'Save new password',
                    large: true,
                    expand: true,
                    loading: _busy,
                    loadingLabel: 'Saving…',
                    onPressed: _save,
                  ),
                ],
              ),
            ),
            const SizedBox(height: BxSpace.md),
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => context.go(Routes.login),
                child: const Text('Back to log in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  final String label;
  final bool met;
  const _RuleChip(this.label, this.met);

  @override
  Widget build(BuildContext context) {
    return BxChip(
      label,
      accent: met ? BxAccent.success : BxAccent.neutral,
      icon: met ? Icons.check_rounded : Icons.circle_outlined,
      dense: true,
    );
  }
}
