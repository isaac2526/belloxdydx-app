import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../core/theme/tokens.dart';
import '../ui/primitives.dart' show BxAccent;

/// ============================================================
/// HOW FAST THE CONNECTION ACTUALLY IS
///
/// "let's be seeing the internet connection speed on the app if
///  possible"
///
/// It is possible, and the honest way to do it is to measure the
/// traffic the app is ALREADY making. A speed test that downloads a
/// test file to find out how fast the connection is has spent a
/// student's airtime to tell them something they could have been told
/// for free — and on a 200 KB/s line it makes the app slower while
/// reporting on how slow the app is.
///
/// So every response the app receives is timed and its size recorded,
/// and this keeps a short rolling window of them. Two numbers come out:
///
///   · **Latency** — how long a small request takes end to end. This is
///     what makes an app feel slow, and on Nigerian mobile data it is
///     usually the number that is bad.
///
///   · **Throughput** — bytes per second, taken only from responses big
///     enough for the number to mean anything. A 400-byte JSON reply
///     over a 300 ms round trip reads as 1.3 KB/s, which is a lie about
///     the line rather than a measurement of it.
///
/// Nothing here ever blocks a request or adds one.
/// ============================================================

/// What a student is shown, in words rather than numbers.
enum BxNetGrade {
  /// No samples yet. Say nothing rather than guess.
  unknown,

  /// The radio is off or nothing is getting through.
  offline,

  /// Working, but painfully. Under ~30 KB/s or over two seconds to
  /// answer.
  poor,

  /// Usable. Notes and questions arrive; a video will struggle.
  fair,

  /// Comfortable for anything the app does.
  good,
}

@immutable
class BxNetSpeed {
  final BxNetGrade grade;

  /// Bytes per second, or 0 when nothing large enough has been seen.
  final double bytesPerSecond;

  /// Round-trip milliseconds for a small request, or 0.
  final int latencyMs;

  /// True when the connection is one nobody pays per megabyte for.
  final bool unmetered;

  const BxNetSpeed({
    this.grade = BxNetGrade.unknown,
    this.bytesPerSecond = 0,
    this.latencyMs = 0,
    this.unmetered = false,
  });

  /// The short line that goes on screen: "Wi-Fi · 1.2 MB/s", or
  /// "Mobile data · slow" when there is nothing solid to quote.
  String get label {
    final where = unmetered ? 'Wi-Fi' : 'Mobile data';
    return switch (grade) {
      BxNetGrade.unknown => where,
      BxNetGrade.offline => 'No connection',
      _ => bytesPerSecond > 0 ? '$where · $rate' : '$where · $word',
    };
  }

  /// Just the rate, for a progress line that already says where it is.
  String get rate {
    final bps = bytesPerSecond;
    if (bps <= 0) return word;
    if (bps < 1024) return '${bps.round()} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).round()} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get word => switch (grade) {
        BxNetGrade.offline => 'offline',
        BxNetGrade.poor => 'slow',
        BxNetGrade.fair => 'ok',
        BxNetGrade.good => 'fast',
        BxNetGrade.unknown => 'checking',
      };

  bool get isSlow =>
      grade == BxNetGrade.poor || grade == BxNetGrade.offline;

  /// The one colour the whole app uses for this reading.
  ///
  /// Green good, amber ok, red bad, red for no line at all. Defined
  /// once, next to the grade that decides it, so the app bar, the vault
  /// and a running download can never disagree about what "slow" looks
  /// like.
  BxAccent get accent => switch (grade) {
        BxNetGrade.offline => BxAccent.danger,
        BxNetGrade.poor => BxAccent.danger,
        BxNetGrade.fair => BxAccent.warning,
        BxNetGrade.good => BxAccent.success,
        BxNetGrade.unknown => BxAccent.neutral,
      };

  Color tint(BxColors c) => switch (grade) {
        BxNetGrade.offline => c.danger,
        BxNetGrade.poor => c.danger,
        BxNetGrade.fair => c.warning,
        BxNetGrade.good => c.success,
        BxNetGrade.unknown => c.muted,
      };

  /// What the reading means for the student, in their words rather than
  /// in megabytes.
  String get plain => switch (grade) {
        BxNetGrade.offline => 'No connection',
        BxNetGrade.poor => 'Bad connection',
        BxNetGrade.fair => 'Connection is ok',
        BxNetGrade.good => 'Good connection',
        BxNetGrade.unknown => 'Checking your connection',
      };
}

/// Under ~30 KB/s the app is not usable for anything but text.
const double _poorBytesPerSecond = 30 * 1024;

/// Over ~300 KB/s everything the app does is comfortable.
const double _goodBytesPerSecond = 300 * 1024;

/// A response has to be at least this big before its rate means
/// anything about the line rather than about the round trip.
const int _minSampleBytes = 8 * 1024;

/// Two seconds to answer a small request is a connection a student can
/// feel, whatever the throughput says.
const int _poorLatencyMs = 2000;
const int _goodLatencyMs = 800;

/// How many samples the rolling window keeps. Short on purpose: a
/// student walking out of a lecture hall changes network in seconds and
/// a long average would still be describing the room they left.
const int _window = 8;

class NetSpeedMeter extends ChangeNotifier {
  final Queue<({int bytes, int millis})> _rates = Queue();
  final Queue<int> _latencies = Queue();

  bool _unmetered = false;
  bool _reachable = true;

  /// The last kind of line we actually saw working.
  ///
  /// When Wi-Fi drops, the platform reports "no connection", so
  /// `_unmetered` is false by the time the offline reading is
  /// published — and a Wi-Fi student was shown crossed-out CELLULAR
  /// bars, which is the shape change this was meant to stop. The kind
  /// of line only changes while there IS one.
  bool _lastLine = false;

  BxNetSpeed _value = const BxNetSpeed();
  BxNetSpeed get value => _value;

  /// Called from the connectivity watcher.
  void setUnmetered(bool v) {
    if (v) _lastLine = true;
    if (_unmetered == v) return;
    _unmetered = v;
    // The line changed underneath us; what was measured on the old one
    // says nothing about the new one.
    _rates.clear();
    _latencies.clear();
    _recompute();
  }

  void setReachable(bool v) {
    if (v) _lastLine = _unmetered;
    if (_reachable == v) return;
    _reachable = v;
    _recompute();
  }

  /// Records one completed response. Never throws, never blocks.
  ///
  /// A response counts towards exactly ONE of the two numbers, decided
  /// by its size, and keeping them apart is the whole of getting this
  /// right. For a small reply the elapsed time IS the round trip, so it
  /// measures latency and says nothing about bandwidth. For a large
  /// transfer the elapsed time is almost all streaming, so it measures
  /// bandwidth and says nothing about latency — counting it as latency
  /// would report a 2 MB download that took a second as a
  /// one-second-latency connection, which is a fast line described as
  /// a slow one.
  void sample({required int bytes, required int millis}) {
    if (millis <= 0) return;
    _reachable = true;
    if (bytes >= _minSampleBytes) {
      _rates.addLast((bytes: bytes, millis: millis));
      while (_rates.length > _window) {
        _rates.removeFirst();
      }
    } else {
      _latencies.addLast(millis);
      while (_latencies.length > _window) {
        _latencies.removeFirst();
      }
    }
    _recompute();
  }

  void _recompute() {
    if (!_reachable) {
      // The kind of line is kept: a phone with its data off should show
      // the bars it will have when it comes back, crossed out.
      _publish(BxNetSpeed(grade: BxNetGrade.offline, unmetered: _lastLine));
      return;
    }

    // Totals, not an average of averages: one 40-byte reply that took
    // 400 ms should not weigh as much as a megabyte that took two
    // seconds.
    var bytes = 0;
    var millis = 0;
    for (final r in _rates) {
      bytes += r.bytes;
      millis += r.millis;
    }
    final bps = millis > 0 ? bytes * 1000 / millis : 0.0;

    // NEAR THE FAST END OF THE WINDOW, BUT NOT THE FASTEST REPLY.
    //
    // A small reply's elapsed time is the line's round trip PLUS
    // whatever the server spent making it — and the website's
    // functions sleep between requests, so one cold start can take
    // three seconds on its own. Read as latency, the median painted a
    // student's perfectly good 4.5G red for as long as the app was
    // open.
    //
    // The fastest reply is the other mistake: one lucky cached answer
    // would then speak for the whole window and call a line that takes
    // three seconds on everything else "fast". A low percentile throws
    // out the cold start without letting a single sample carry the
    // verdict — it takes two fast replies to move the reading.
    var latency = 0;
    if (_latencies.isNotEmpty) {
      final sorted = _latencies.toList()..sort();
      latency = sorted[(sorted.length - 1) ~/ 4];
    }

    final hasLatency = _latencies.isNotEmpty;

    final BxNetGrade grade;
    if (!hasLatency && _rates.isEmpty) {
      grade = BxNetGrade.unknown;
    } else if (bps > 0) {
      // Throughput decides when there is throughput to go on, but a
      // line that takes two seconds to answer a small request is slow
      // however fast it then streams — that delay is what a student
      // feels on every tap.
      if (bps < _poorBytesPerSecond ||
          (hasLatency && latency >= _poorLatencyMs)) {
        grade = BxNetGrade.poor;
      } else if (bps >= _goodBytesPerSecond &&
          (!hasLatency || latency <= _goodLatencyMs)) {
        grade = BxNetGrade.good;
      } else {
        grade = BxNetGrade.fair;
      }
    } else if (latency >= _poorLatencyMs) {
      grade = BxNetGrade.poor;
    } else if (latency <= _goodLatencyMs) {
      grade = BxNetGrade.good;
    } else {
      grade = BxNetGrade.fair;
    }

    _publish(BxNetSpeed(
      grade: grade,
      bytesPerSecond: bps,
      latencyMs: latency,
      unmetered: _unmetered,
    ));
  }

  void _publish(BxNetSpeed next) {
    final same = next.grade == _value.grade &&
        next.unmetered == _value.unmetered &&
        // Quantised, so a chip does not flicker on every request. A
        // rate that moved by less than a fifth is the same rate as far
        // as a student reading it is concerned.
        _closeEnough(next.bytesPerSecond, _value.bytesPerSecond);
    _value = next;
    if (!same) notifyListeners();
  }

  static bool _closeEnough(double a, double b) {
    if (a == b) return true;
    if (a <= 0 || b <= 0) return false;
    final bigger = a > b ? a : b;
    return (a - b).abs() / bigger < 0.2;
  }
}
