import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../ui/ui.dart';
import 'app_drawer.dart';
import 'net_chip.dart';

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
    // Hold the phone layout until the window has actually been measured.
    // Choosing the rail from an unmeasured first frame and the bar from
    // the second shifts every pixel of content sideways by the rail's
    // width, which is what a startup "drift" looks like.
    final wide = !context.sizeUnknown && context.isWide;

    // The drawer hangs here, on the SHELL's Scaffold, and is opened by
    // key from inside the tabs — each of which builds its own Scaffold,
    // so Scaffold.of() from a tab would find the inner one and never
    // see a drawer hung on this outer one.
    final key = ref.watch(shellScaffoldKey);

    if (wide) {
      return Scaffold(
        key: key,
        drawer: const AppDrawer(),
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
      key: key,
      drawer: const AppDrawer(),
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
class BxAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final Widget? bottom;

  /// Offers the drawer when there is nothing to go back to. Turned off
  /// on a screen that owns its own leading control.
  final bool showMenu;

  const BxAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
    this.showMenu = true,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(bottom == null ? 56 : 104);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    final canPop = showBack && Navigator.of(context).canPop();

    // Back always wins. The drawer is an ADDITIONAL way in, offered
    // only where the slot is free — so nothing that worked before
    // changes, and the deeper screens keep their back button.
    final menu = !canPop &&
        showMenu &&
        ref.watch(shellScaffoldKey).currentState?.hasDrawer == true;

    return AppBar(
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : menu
              ? IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: 'More',
                  onPressed: () => openAppDrawer(ref),
                )
              : null,
      titleSpacing: (canPop || menu) ? 0 : 16,
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
      actions: [
        // Only when there is something a student would want to know.
        // "Wi-Fi · 4.1 MB/s" sitting in the chrome all day is clutter;
        // "Mobile data · slow" the moment the line goes bad is the
        // difference between "this app is broken" and "my network is".
        const Padding(
          padding: EdgeInsets.only(right: BxSpace.xxs),
          child: BxNetChip(),
        ),
        ...actions,
        const SizedBox(width: BxSpace.xs),
      ],
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
      // Never e.toString(): a PostgrestException prints its own schema
      // detail and a ClientException prints the full request URL.
      if (mounted) {
        setState(() => _error = e is BxError
            ? e.message
            : ref.read(backendProvider).faultFor(e).message);
      }
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
