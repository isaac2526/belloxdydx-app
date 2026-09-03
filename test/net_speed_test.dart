import 'package:belloxdydx/data/net_speed.dart';
import 'package:flutter_test/flutter_test.dart';

/// ============================================================
/// THE CONNECTION READING
///
/// "let's be seeing the internet connection speed on the app if
///  possible"
///
/// The whole design rests on one refusal: no synthetic speed test.
/// Downloading a test file to find out how fast the line is spends a
/// student's airtime to tell them their airtime is slow, and on a
/// 200 KB/s connection it makes the app slower while reporting on how
/// slow the app is. So the reading comes from responses the app was
/// going to fetch anyway — which means it has to be right about which
/// of those responses can say anything about the line.
/// ============================================================
void main() {
  late NetSpeedMeter meter;
  setUp(() => meter = NetSpeedMeter());
  tearDown(() => meter.dispose());

  group('what a sample is allowed to claim', () {
    test('nothing measured says nothing', () {
      expect(meter.value.grade, BxNetGrade.unknown);
      expect(meter.value.bytesPerSecond, 0);
    });

    test('a tiny reply never sets a throughput number', () {
      // A 400-byte JSON reply over a 300 ms round trip reads as
      // 1.3 KB/s. That is a description of the round trip, not of the
      // line, and quoting it to a student would be a lie.
      meter.sample(bytes: 400, millis: 300);
      expect(meter.value.bytesPerSecond, 0,
          reason: 'a small response measures latency, not bandwidth');
      expect(meter.value.latencyMs, 300);
      expect(meter.value.grade, isNot(BxNetGrade.unknown),
          reason: 'it still says something — it timed the round trip');
    });

    test('a large transfer never sets a latency number', () {
      // The other half of the same rule, and the one that is easy to
      // get wrong: two megabytes that took a second is a FAST line, and
      // reading that second as latency would report it as a slow one.
      meter.sample(bytes: 2 * 1024 * 1024, millis: 1000);
      expect(meter.value.latencyMs, 0,
          reason: 'elapsed time on a big transfer is streaming, not '
              'round trip');
      expect(meter.value.grade, BxNetGrade.good);
    });

    test('a big transfer does', () {
      meter.sample(bytes: 2 * 1024 * 1024, millis: 1000);
      expect(meter.value.bytesPerSecond, closeTo(2 * 1024 * 1024, 1));
      expect(meter.value.grade, BxNetGrade.good);
    });

    test('a zero-length interval is discarded, not divided by', () {
      meter.sample(bytes: 1024 * 1024, millis: 0);
      expect(meter.value.grade, BxNetGrade.unknown);
    });
  });

  group('the grade a student is shown', () {
    test('a slow line is slow even when it eventually streams', () {
      // The line moves bytes well once it gets going — 4 MB/s — but it
      // takes three seconds to answer anything. That delay is what a
      // student feels on every tap, so it wins.
      meter.sample(bytes: 4 * 1024 * 1024, millis: 1000);
      meter.sample(bytes: 600, millis: 3000);
      expect(meter.value.grade, BxNetGrade.poor);
      expect(meter.value.isSlow, isTrue);
    });

    test('a trickle is slow', () {
      meter.sample(bytes: 20 * 1024, millis: 1500);
      expect(meter.value.grade, BxNetGrade.poor);
    });

    test('a usable middle is neither', () {
      meter.sample(bytes: 100 * 1024, millis: 800);
      expect(meter.value.grade, BxNetGrade.fair);
      expect(meter.value.isSlow, isFalse);
    });

    test('losing the radio says so at once', () {
      meter.sample(bytes: 2 * 1024 * 1024, millis: 500);
      expect(meter.value.grade, BxNetGrade.good);
      meter.setReachable(false);
      expect(meter.value.grade, BxNetGrade.offline);
      expect(meter.value.label, 'No connection');
    });
  });

  group('the window follows the student', () {
    test('changing network throws the old measurements away', () {
      // A student walking out of a lecture hall changes network in
      // seconds. An average that still includes the Wi-Fi they left is
      // describing a room they are not in.
      meter.sample(bytes: 4 * 1024 * 1024, millis: 500);
      expect(meter.value.grade, BxNetGrade.good);
      meter.setUnmetered(true);
      expect(meter.value.grade, BxNetGrade.unknown,
          reason: 'nothing has been measured on the new line yet');
    });

    test('totals are used, not an average of averages', () {
      // One fast small transfer must not outvote one slow large one.
      meter.sample(bytes: 16 * 1024, millis: 10);   // 1.6 MB/s
      meter.sample(bytes: 1024 * 1024, millis: 10000); // 100 KB/s
      final bps = meter.value.bytesPerSecond;
      final total = (16 * 1024 + 1024 * 1024) * 1000 / 10010;
      expect(bps, closeTo(total, 1),
          reason: 'the honest rate is total bytes over total time');
    });

    test('the window is short enough to forget', () {
      for (var i = 0; i < 20; i++) {
        meter.sample(bytes: 10 * 1024, millis: 2500);
      }
      expect(meter.value.grade, BxNetGrade.poor);
      for (var i = 0; i < 20; i++) {
        meter.sample(bytes: 4 * 1024 * 1024, millis: 400);
      }
      expect(meter.value.grade, BxNetGrade.good,
          reason: 'a line that got better must be allowed to say so');
    });
  });

  group('what it actually says on screen', () {
    test('the rate reads in units a person uses', () {
      expect(const BxNetSpeed(bytesPerSecond: 900).rate, '900 B/s');
      expect(const BxNetSpeed(bytesPerSecond: 90 * 1024).rate, '90 KB/s');
      expect(
        const BxNetSpeed(bytesPerSecond: 3 * 1024 * 1024).rate,
        '3.0 MB/s',
      );
    });

    test('it names the line the student is paying for', () {
      const wifi = BxNetSpeed(
        grade: BxNetGrade.good,
        bytesPerSecond: 2 * 1024 * 1024,
        unmetered: true,
      );
      expect(wifi.label, 'Wi-Fi · 2.0 MB/s');

      const data = BxNetSpeed(
        grade: BxNetGrade.poor,
        bytesPerSecond: 12 * 1024,
      );
      expect(data.label, 'Mobile data · 12 KB/s');
    });

    test('with no throughput it uses a word rather than a wrong number',
        () {
      const latencyOnly = BxNetSpeed(grade: BxNetGrade.poor, latencyMs: 3000);
      expect(latencyOnly.label, 'Mobile data · slow');
    });

    test('an unknown reading says nothing at all', () {
      expect(const BxNetSpeed().label, 'Mobile data');
    });
  });

  group('it does not shout', () {
    test('a rate that barely moved does not wake the widget tree', () {
      var notifications = 0;
      meter.addListener(() => notifications++);
      meter.sample(bytes: 1024 * 1024, millis: 1000);
      final first = notifications;
      expect(first, greaterThan(0));
      // Within a fifth of the same rate: the same rate, as far as
      // anybody reading it is concerned.
      meter.sample(bytes: 1024 * 1024, millis: 1010);
      meter.sample(bytes: 1024 * 1024, millis: 1020);
      expect(notifications, first,
          reason: 'a chip that flickers on every request is worse than no '
              'chip');
    });

    test('a real change does', () {
      var notifications = 0;
      meter.sample(bytes: 4 * 1024 * 1024, millis: 500);
      meter.addListener(() => notifications++);
      meter.sample(bytes: 10 * 1024, millis: 3000);
      expect(notifications, greaterThan(0));
    });
  });
}
