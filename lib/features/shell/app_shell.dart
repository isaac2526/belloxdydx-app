import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../ui/ui.dart';

/// ============================================================
/// THE SHELL
/// Six destinations, mirroring the website's sidebar. On a phone they
/// sit in a bottom bar above the home indicator; on a tablet or in
/// landscape they become a rail, so the app is usable on every screen
/// the student might own.
/// ============================================================

class _Dest {
  final String label;
  final IconData icon;
  final IconData active;
  const _Dest(this.label, this.icon, this.active);
}

const _destinations = <_Dest>[
  _Dest('Home', Icons.grid_view_outlined, Icons.grid_view_rounded),
  _Dest('Courses', Icons.menu_book_outlined, Icons.menu_book_rounded),
  _Dest('Revise', Icons.track_changes_outlined, Icons.track_changes_rounded),
  _Dest('Bello AI', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
  _Dest('Ranks', Icons.emoji_events_outlined, Icons.emoji_events_rounded),
  _Dest('You', Icons.person_outline_rounded, Icons.person_rounded),
];

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  void _go(int index) => shell.goBranch(
        index,
        initialLocation: index == shell.currentIndex,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final wide = context.isWide;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.active),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: c.line),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.active),
                label: d.label,
                tooltip: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// The bar every inner screen uses, so titles, back buttons and actions
/// line up across the whole app.
class BxAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final Widget? bottom;

  const BxAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(bottom == null ? 56 : 104);

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final canPop = showBack && Navigator.of(context).canPop();
    return AppBar(
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      titleSpacing: canPop ? 0 : 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: BxType.h3(c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle!,
                style: BxType.tiny(c.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
      actions: [...actions, const SizedBox(width: BxSpace.xs)],
      bottom: bottom == null
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    BxSpace.md, 0, BxSpace.md, BxSpace.xs),
                child: bottom!,
              ),
            ),
    );
  }
}

/// Standard page padding so every screen has the same margins.
class BxPage extends StatelessWidget {
  final Widget child;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry padding;
  final bool scrollable;

  const BxPage({
    super.key,
    required this.child,
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(
        BxSpace.md, BxSpace.md, BxSpace.md, BxSpace.xxxl),
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final body = scrollable
        ? SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: child,
              ),
            ),
          )
        : Padding(padding: padding, child: child);

    if (onRefresh == null) return body;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: context.bx.gold,
      backgroundColor: context.bx.surface,
      child: body,
    );
  }
}

/// A small pill that reports which backend path is live. It is not
/// decoration: after the SQL migration lands this is how you confirm at
/// a glance that student traffic stopped going through Vercel.
class BackendModePill extends ConsumerWidget {
  const BackendModePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(backendModeProvider);
    final direct = mode.name == 'direct';
    return BxChip(
      direct ? 'Direct' : 'Via website',
      accent: direct ? BxAccent.success : BxAccent.neutral,
      icon: direct ? Icons.bolt_rounded : Icons.cloud_outlined,
      dense: true,
    );
  }
}

/// Opens a live class test from a share code or deep link.
class LiveTestEntry extends ConsumerStatefulWidget {
  final String code;
  const LiveTestEntry({super.key, required this.code});

  @override
  ConsumerState<LiveTestEntry> createState() => _LiveTestEntryState();
}

class _LiveTestEntryState extends ConsumerState<LiveTestEntry> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      final id = await ref
          .read(assessmentRepoProvider)
          .startShareCode(widget.code);
      if (!mounted) return;
      context.pushReplacement('/cbt/$id');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BxAppBar(title: 'Live test', subtitle: widget.code.toUpperCase()),
      body: BxPage(
        child: _error == null
            ? const Padding(
                padding: EdgeInsets.only(top: BxSpace.xxxl),
                child: BxThinking(message: 'Opening the live test…'),
              )
            : BxErrorState(
                title: 'Could not open this test',
                message: _error!,
                onRetry: () {
                  setState(() => _error = null);
                  _open();
                },
              ),
      ),
    );
  }
}
