import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/security.dart';
import '../../ui/ui.dart';
import '../auth/auth_brand.dart';

/// ============================================================
/// THE LOCK
///
/// Drawn OVER the whole app rather than pushed as a route, for two
/// reasons: nothing can navigate around it, and the screen underneath
/// keeps its state, so a student who steps away mid-question comes back
/// to the same question rather than to the dashboard.
///
/// What it asks for is the phone's own fingerprint, face or screen PIN.
/// Never the account password. The student proved that at sign-in, and
/// asking for it every few minutes trains them to type it in a lecture
/// hall with forty people around.
/// ============================================================

class LockOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const LockOverlay({super.key, required this.child});

  @override
  ConsumerState<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<LockOverlay> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final locked = lock == BxLockState.locked ||
        lock == BxLockState.enrolling ||
        lock == BxLockState.asking;

    // The moment the lock comes down, ask — so the common case is one
    // touch of the sensor and back to work, with no button to find.
    if ((lock == BxLockState.locked || lock == BxLockState.enrolling) &&
        !_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(appLockProvider.notifier).unlock();
      });
    }
    if (lock == BxLockState.open) _asked = false;

    return Stack(
      children: [
        // Every pointer and key event in the app passes through here.
        // This is what makes "five minutes of inactivity" mean
        // inactivity rather than five minutes.
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => ref.read(appLockProvider.notifier).touch(),
          onPointerMove: (_) => ref.read(appLockProvider.notifier).touch(),
          child: widget.child,
        ),
        if (locked)
          Positioned.fill(
            child: _LockFace(
              asking: lock == BxLockState.asking,
              enrolling: lock == BxLockState.enrolling,
            ),
          ),
      ],
    );
  }
}

class _LockFace extends ConsumerWidget {
  final bool asking;
  final bool enrolling;
  const _LockFace({required this.asking, this.enrolling = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    return Material(
      color: c.ground,
      child: SafeArea(
        // Scrollable, and centred only when there is room to centre it.
        //
        // This is the one screen in the app a student cannot navigate
        // away from, so an overflow here is not a cosmetic complaint —
        // it is the Unlock button pushed off the bottom of the screen
        // with no way to reach it. Measured: on a 320x568 phone at the
        // largest text size the app allows, the enrolment wording ran
        // 40 pixels past the bottom.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                    padding: const EdgeInsets.all(BxSpace.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const BxAuthBrand(size: 72),
                        const SizedBox(height: BxSpace.lg),
                        Text(
                          enrolling ? 'Lock this to you' : 'Locked',
                          style: BxType.h1(c.ink),
                        ),
                        const SizedBox(height: BxSpace.xs),
                        Text(
                          enrolling
                              ? 'From now on Belloxdydx opens with your own '
                                  'fingerprint, face or screen PIN — the same one '
                                  'that opens this phone. Nobody who picks it up '
                                  'gets into your account. Touch the sensor once '
                                  'to set it.'
                              : 'You stepped away, so we closed it. Your '
                                  'fingerprint opens it again — no password '
                                  'needed.',
                          style: BxType.body(c.inkSoft),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: BxSpace.lg),
                        BxButton(
                          enrolling ? 'Set it now' : 'Unlock',
                          icon: Icons.fingerprint_rounded,
                          loading: asking,
                          loadingLabel: 'Waiting for the sensor…',
                          expand: true,
                          large: true,
                          onPressed: asking
                              ? null
                              : () =>
                                  ref.read(appLockProvider.notifier).unlock(),
                        ),
                        const SizedBox(height: BxSpace.sm),
                        if (enrolling)
                          // A wet sensor must never be the reason a student
                          // cannot open an app they have just paid for. The
                          // lock stays on; this only means "not this second".
                          TextButton(
                            onPressed: asking
                                ? null
                                : () => ref
                                    .read(appLockProvider.notifier)
                                    .skipEnrolment(),
                            child:
                                Text('Not now', style: BxType.small(c.muted)),
                          )
                        else
                          TextButton(
                            onPressed: () =>
                                ref.read(sessionProvider.notifier).signOut(),
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
