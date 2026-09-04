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

  /// Icon and colour only, with the reading on a long-press.
  ///
  /// "Mobile data · slow" is eleven characters of chrome in an AppBar
  /// action slot, and an AppBar gives its actions all the room they ask
  /// for before the title gets any. On a 320dp phone at the largest
  /// text the app allows, the title was crushed to about 56dp — so the
  /// student lost the name of the screen they were on at exactly the
  /// moment their line went bad. The colour already carries the
  /// meaning; the words belong where there is room for them.
  final bool iconOnly;

  const BxNetChip({
    super.key,
    this.onlyWhenItMatters = true,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final net = ref.watch(netSpeedProvider);
    if (net.grade == BxNetGrade.unknown) return const SizedBox.shrink();
    if (onlyWhenItMatters && !net.isSlow) return const SizedBox.shrink();

    final icon = switch (net.grade) {
      BxNetGrade.offline => Icons.cloud_off_rounded,
      BxNetGrade.poor => Icons.network_check_rounded,
      BxNetGrade.fair => Icons.wifi_2_bar_rounded,
      _ => net.unmetered
          ? Icons.wifi_rounded
          : Icons.signal_cellular_alt_rounded,
    };

    if (iconOnly) {
      final c = context.bx;
      return Tooltip(
        message: net.label,
        child: Semantics(
          label: net.label,
          child: Icon(
            icon,
            size: 18,
            color: switch (net.grade) {
              BxNetGrade.offline => c.danger,
              BxNetGrade.poor => c.warning,
              BxNetGrade.fair => c.info,
              _ => c.success,
            },
          ),
        ),
      );
    }

    return BxChip(
      net.label,
      dense: true,
      icon: icon,
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
        // Flexible, because this line sits beside other things in a
        // narrow box — a progress caption on a 320dp phone at the
        // largest text the app allows. Left rigid it overflowed its own
        // row by 54 pixels and painted the yellow-and-black stripe
        // across a running download.
        Flexible(
          child: Text(
            net.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BxType.tiny(net.isSlow ? c.warning : c.muted),
          ),
        ),
      ],
    );
  }
}
