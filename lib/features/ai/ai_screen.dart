import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// ============================================================
/// BELLO AI — THE 24/7 TUTOR TAB
///
/// A tutor who never sleeps and never makes you feel small for asking
/// the same thing twice. The conversation lives in this screen's memory
/// only: nothing is written anywhere, and "New chat" wipes it clean.
///
/// The thinking state is deliberate work, not a spinner — three dots
/// breathing in sequence under a line that says what is happening, so
/// a slow network feels like someone typing rather than a frozen app.
/// ============================================================

const _suggestions = <String>[
  'Explain limits simply',
  'Solve this past question step by step',
  "Summarise Newton's laws",
  'Quiz me on PHY 101',
];

const _footerNote =
    'Bello AI is a study helper. Check anything important against your notes.';

/// The reply may arrive as HTML, as markdown-ish plain text, or as plain
/// prose. Anything already carrying tags is passed through; everything
/// else is escaped first so a student's own angle brackets cannot become
/// markup, then given back its line breaks, bold and code spans.
final _looksLikeHtml = RegExp(
  r'<(p|br|div|ul|ol|li|strong|em|b|i|h[1-6]|code|pre|table|blockquote|span)\b',
  caseSensitive: false,
);

String _toHtml(String raw) {
  if (_looksLikeHtml.hasMatch(raw)) return raw;
  final escaped = raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final bolded = escaped.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*', dotAll: true),
    (m) => '<strong>${m[1]}</strong>',
  );
  final coded = bolded.replaceAllMapped(
    RegExp(r'`([^`\n]+)`'),
    (m) => '<code>${m[1]}</code>',
  );
  return coded.replaceAll('\n', '<br>');
}

@immutable
class _Msg {
  final String role; // 'user' or 'model' — exactly what askAi expects.
  final String text;
  const _Msg.user(this.text) : role = 'user';
  const _Msg.model(this.text) : role = 'model';

  bool get isUser => role == 'user';
}

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  bool _busy = false;
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_watchInput);
  }

  @override
  void dispose() {
    _input.removeListener(_watchInput);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _watchInput() {
    final has = _input.text.trim().isNotEmpty;
    if (has != _canSend) setState(() => _canSend = has);
  }

  // ---------------------------------------------------------- actions

  void _scrollToLatest() {
    // The list is reversed, so the newest message sits at offset zero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (reduceMotion(context)) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0, duration: BxDuration.base, curve: BxCurves.enter);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _messages.add(_Msg.user(text));
      _busy = true;
    });
    _input.clear();
    _scrollToLatest();

    final history = [
      for (final m in _messages) (role: m.role, text: m.text),
    ];

    String reply;
    try {
      reply = await ref.read(engageRepoProvider).askAi(history);
    } catch (_) {
      // askAi already hands back student-safe text; this is the last net.
      reply = 'Could not reach Bello AI just now. '
          'Check your connection and ask again.';
    }
    if (!mounted) return;

    setState(() {
      _messages.add(_Msg.model(reply));
      _busy = false;
    });
    _scrollToLatest();
  }

  void _useSuggestion(String s) {
    _input.value = TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
    _focus.requestFocus();
  }

  Future<void> _newChat() async {
    final ok = await bxConfirm(
      context,
      title: 'Start a new chat?',
      message: 'This clears what you and Bello have said so far. '
          'Nothing here is saved, so copy anything you still need first.',
      confirmLabel: 'New chat',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _messages.clear();
      _input.clear();
    });
  }

  void _gate() =>
      showActivationGate(context, () => context.push(Routes.activate));

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final activated = ref.watch(profileProvider).isActivated;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: BxSpace.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Bello AI', style: BxType.h3(c.ink)),
            const SizedBox(height: 2),
            const BxEyebrow('Your 24/7 tutor'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: _messages.isEmpty || _busy ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: BxSwitcher(
                  child: activated ? _chat(context) : _locked(context),
                ),
              ),
            ),
          ),
          _Composer(
            controller: _input,
            focusNode: _focus,
            canSend: _canSend && !_busy,
            locked: !activated,
            onSend: _send,
            onLockedTap: _gate,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- states

  Widget _locked(BuildContext context) => BxPage(
        key: const ValueKey('locked'),
        child: BxEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Bello AI opens when you activate',
          message: 'Your activation key turns on the tutor that answers at '
              '2am — explanations, past questions, quick quizzes, no queue. '
              'Look around all you like in the meantime.',
          actionLabel: 'Activate',
          onAction: () => context.push(Routes.activate),
        ),
      );

  Widget _chat(BuildContext context) {
    if (_messages.isEmpty && !_busy) {
      return _Opener(key: const ValueKey('opener'), onPick: _useSuggestion);
    }

    final extra = _busy ? 1 : 0;
    return ListView.builder(
      key: const ValueKey('thread'),
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          BxSpace.md, BxSpace.md, BxSpace.md, BxSpace.md),
      itemCount: _messages.length + extra,
      itemBuilder: (context, i) {
        if (_busy && i == 0) {
          return const Padding(
            padding: EdgeInsets.only(top: BxSpace.sm),
            child: _ThinkingBubble(),
          );
        }
        final m = _messages[_messages.length - 1 - (i - extra)];
        return Padding(
          padding: const EdgeInsets.only(top: BxSpace.sm),
          child: _Bubble(m),
        );
      },
    );
  }
}

// ============================================================ opener

class _Opener extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _Opener({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return BxPage(
      child: BxStagger(
        children: [
          BxCard(
            padding: const EdgeInsets.all(BxSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _AiMark(size: 34),
                    const SizedBox(width: BxSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BxEyebrow('Bello AI'),
                          const SizedBox(height: 2),
                          Text('Ask me anything, any time',
                              style: BxType.h2(c.ink)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BxSpace.md),
                Text(
                  'I explain topics in plain English, walk through past '
                  'questions step by step, and quiz you when you want to '
                  'test yourself. Ask in your own words — no need to sound '
                  'like a textbook.',
                  style: BxType.body(c.inkSoft),
                ),
                const SizedBox(height: BxSpace.xs),
                Text(
                  'Small daily reading beats midnight panic. Start with one '
                  'question.',
                  style: BxType.small(c.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BxSectionHeader(
                title: 'Try one of these',
                eyebrow: 'Starters',
                padding: EdgeInsets.only(bottom: BxSpace.sm),
              ),
              Wrap(
                spacing: BxSpace.xs,
                runSpacing: BxSpace.xs,
                children: [
                  for (final s in _suggestions)
                    BxChip(
                      s,
                      icon: Icons.north_east_rounded,
                      onTap: () => onPick(s),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================ bubbles

class _AiMark extends StatelessWidget {
  final double size;
  const _AiMark({this.size = 28});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.goldTint,
        shape: BoxShape.circle,
        border: Border.all(color: c.gold.withValues(alpha: 0.42)),
      ),
      child:
          Icon(Icons.auto_awesome_rounded, size: size * 0.5, color: c.goldDeep),
    );
  }
}

/// The shared bubble frame: gold and right for the student, a soft
/// surface and left for Bello, never wider than a comfortable measure.
class _BubbleShell extends StatelessWidget {
  final bool isUser;
  final Widget child;
  const _BubbleShell({required this.isUser, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? BxSpace.xxl : 0,
        right: isUser ? 0 : BxSpace.xxl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _AiMark(),
            const SizedBox(width: BxSpace.xs),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: BxCard(
                accent: isUser ? BxAccent.gold : BxAccent.neutral,
                fill: isUser ? null : c.surfaceAlt,
                padding: const EdgeInsets.symmetric(
                    horizontal: BxSpace.md, vertical: BxSpace.sm),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg message;
  const _Bubble(this.message);

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final ink = message.isUser ? c.ink : c.inkSoft;
    return _BubbleShell(
      isUser: message.isUser,
      child: BxHtml(
        _toHtml(message.text),
        textStyle: BxType.body(ink),
      ),
    );
  }
}

/// The thinking state: three dots fading in sequence, and a line that
/// says who is working. It replaces the moment a spinner would waste.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// A triangle wave per dot, each one a beat behind the last.
  double _opacityFor(double t, int index) {
    final p = (t - index * 0.18) % 1.0;
    final ramp = p < 0.5 ? p * 2 : (1 - p) * 2;
    return 0.22 + 0.78 * Curves.easeInOut.transform(ramp.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final still = reduceMotion(context);

    Widget dot(int i, double opacity) => Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
            ),
          ),
        );

    final dots = still
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < 3; i++) dot(i, 1)],
          )
        : AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) dot(i, _opacityFor(_c.value, i)),
              ],
            ),
          );

    return _BubbleShell(
      isUser: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dots,
          const SizedBox(width: BxSpace.sm),
          Flexible(
            child: Text('Bello is thinking…', style: BxType.small(c.muted)),
          ),
        ],
      ),
    );
  }
}

// ============================================================ composer

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool locked;
  final VoidCallback onSend;
  final VoidCallback onLockedTap;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.locked,
    required this.onSend,
    required this.onLockedTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final enabled = locked ? false : canSend;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  BxSpace.md, BxSpace.xs, BxSpace.md, BxSpace.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        // A hint is not a name: once the student types a
                        // character it disappears, and the most important
                        // input in the app is announced as an unlabelled
                        // text field for the rest of the conversation.
                        child: Semantics(
                          label: locked
                              ? 'Activate to chat with Bello'
                              : 'Ask Bello anything',
                          textField: true,
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            readOnly: locked,
                            onTap: locked ? onLockedTap : null,
                            minLines: 1,
                            maxLines: 5,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.newline,
                            style: BxType.body(c.ink),
                            decoration: InputDecoration(
                              hintText: locked
                                  ? 'Activate to chat with Bello'
                                  : 'Ask Bello anything…',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: BxSpace.md, vertical: BxSpace.sm),
                              prefixIcon: locked
                                  ? Icon(Icons.lock_outline_rounded,
                                      size: 18, color: c.muted)
                                  : null,
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 38, minHeight: 38),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: BxSpace.xs),
                      IconButton(
                        tooltip: 'Send',
                        onPressed: locked
                            ? onLockedTap
                            : (enabled
                                ? () {
                                    HapticFeedback.selectionClick();
                                    onSend();
                                  }
                                : null),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                        style: IconButton.styleFrom(
                          foregroundColor: c.goldDeep,
                          disabledForegroundColor: c.muted,
                          backgroundColor: c.goldTint,
                          disabledBackgroundColor: c.surfaceAlt,
                          side: BorderSide(
                              color: enabled || locked
                                  ? c.gold.withValues(alpha: 0.42)
                                  : c.line),
                          padding: const EdgeInsets.all(BxSpace.sm),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _footerNote,
                    style: BxType.tiny(c.muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
