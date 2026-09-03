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
    final locked = lock == BxLockState.locked || lock == BxLockState.asking;

    // The moment the lock comes down, ask — so the common case is one
    // touch of the sensor and back to work, with no button to find.
    if (lock == BxLockState.locked && !_asked) {
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
            child: _LockFace(asking: lock == BxLockState.asking),
          ),
      ],
    );
  }
}

class _LockFace extends ConsumerWidget {
  final bool asking;
  const _LockFace({required this.asking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.bx;
    return Material(
      color: c.ground,
      child: SafeArea(
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
                  Text('Locked', style: BxType.h1(c.ink)),
                  const SizedBox(height: BxSpace.xs),
                  Text(
                    'You stepped away, so we closed it. Your fingerprint '
                    'opens it again — no password needed.',
                    style: BxType.body(c.inkSoft),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: BxSpace.lg),
                  BxButton(
                    'Unlock',
                    icon: Icons.fingerprint_rounded,
                    loading: asking,
                    loadingLabel: 'Waiting for the sensor…',
                    expand: true,
                    large: true,
                    onPressed: asking
                        ? null
                        : () => ref.read(appLockProvider.notifier).unlock(),
                  ),
                  const SizedBox(height: BxSpace.sm),
                  TextButton(
                    onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                    child: Text('Sign out instead', style: BxType.small(c.muted)),
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
