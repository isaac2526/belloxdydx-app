import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/net_speed.dart';
import '../../ui/ui.dart';

/// ============================================================
/// THE CONNECTION CHIP
///
/// "let's be seeing the internet connection speed on the app if
///  possible"
///
/// One small line, measured from traffic the app is already making —
/// never a speed test, which would spend a student's airtime to tell
/// them their airtime is slow.
///
/// It stays out of the way when there is nothing worth saying. A good
/// connection reports itself once and then sits quiet; a bad one is
/// worth a colour, because "the app is slow" and "your line is slow"
/// are different problems and only one of them is ours.
/// ============================================================

class BxNetChip extends ConsumerWidget {
  /// When true the chip is only drawn if there is something the student
  /// would want to know — offline, or slow. Used in the app bar, where
  /// a permanent "Wi-Fi · 4.1 MB/s" is clutter.
  final bool onlyWhenItMatters;

  const BxNetChip({super.key, this.onlyWhenItMatters = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final net = ref.watch(netSpeedProvider);
    if (net.grade == BxNetGrade.unknown) return const SizedBox.shrink();
    if (onlyWhenItMatters && !net.isSlow) return const SizedBox.shrink();

    return BxChip(
      net.label,
      dense: true,
      icon: switch (net.grade) {
        BxNetGrade.offline => Icons.cloud_off_rounded,
        BxNetGrade.poor => Icons.network_check_rounded,
        BxNetGrade.fair => Icons.wifi_2_bar_rounded,
        _ => net.unmetered ? Icons.wifi_rounded : Icons.signal_cellular_alt_rounded,
      },
      accent: switch (net.grade) {
        BxNetGrade.offline => BxAccent.danger,
        BxNetGrade.poor => BxAccent.warning,
        BxNetGrade.fair => BxAccent.info,
        _ => BxAccent.success,
      },
    );
  }
}

/// The same reading as a plain line, for a place that already has its
/// own chrome — the Vault's header, a download's progress row.
class BxNetLine extends ConsumerWidget {
  const BxNetLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final net = ref.watch(netSpeedProvider);
    if (net.grade == BxNetGrade.unknown) return const SizedBox.shrink();
    final c = context.bx;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          net.grade == BxNetGrade.offline
              ? Icons.cloud_off_rounded
              : net.unmetered
                  ? Icons.wifi_rounded
                  : Icons.signal_cellular_alt_rounded,
          size: 13,
          color: net.isSlow ? c.warning : c.muted,
        ),
        const SizedBox(width: 4),
        Text(
          net.label,
          style: BxType.tiny(net.isSlow ? c.warning : c.muted),
        ),
      ],
    );
  }
}
