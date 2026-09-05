import 'dart:math';

/// ============================================================
/// DEALING AN OFFLINE ROUND
///
/// "the practice part, in offline it's repeating almost the same
///  question and somehow I'm not seeing images questions"
///
/// Both halves of that sentence are this file. It is kept apart from
/// the repository and kept pure — a bank, a memory, and what the phone
/// holds go in; a round comes out — so a test can deal three rounds
/// and read what a student would have been asked.
/// ============================================================

/// Deals one offline round from the bank on the phone.
///
/// Two rules, in this order:
///
///   1. **Not seen lately first.** Everything the phone has not dealt
///      recently is shuffled and taken before anything it has. The
///      recently-dealt ones are only reached for when the bank is
///      smaller than the round — and then the LEAST recent first.
///      A memoryless shuffle of seventy-five dealt the same handful
///      round after round; this walks the whole bank before it
///      repeats one.
///
///   2. **A question whose media is on the phone comes first.** One
///      whose diagram or voice note never came down is not dropped —
///      it is still a question, and a NEW question with a missing
///      picture still teaches more than one the student answered ten
///      minutes ago. So the order is: unseen and whole, then unseen
///      but missing something, then seen. A student only meets the
///      grey "not on this phone yet" box once the whole bank has been
///      through once.
///
/// Pure, so a test can hand it a bank and a memory and read what it
/// deals.
List<Map<String, dynamic>> dealOfflineRound(
  List<Map<String, dynamic>> bank, {
  required int count,
  required List<String> recentlyServed,
  /// True when this picture is on the phone. Defaults to "yes" so a
  /// caller that has no store to ask still gets a sane deal.
  bool Function(String url)? pictureIsHeld,
  Random? random,
}) {
  if (bank.isEmpty) return const [];
  final n = count.clamp(1, bank.length);
  final rng = random ?? Random();
  final recentRank = <String, int>{
    for (var i = 0; i < recentlyServed.length; i++) recentlyServed[i]: i,
  };
  String idOf(Map<String, dynamic> r) => '${r['id'] ?? ''}';
  final held = pictureIsHeld ?? (String _) => true;
  bool picturesHere(Map<String, dynamic> r) {
    for (final key in const [
      'question_image_url',
      'questionImageUrl',
      // The explanation opens the moment an answer is committed, so a
      // missing explanation diagram lands on the student just as hard
      // as a missing question one.
      'explanation_image_url',
      'explanationImageUrl',
      'question_audio_url',
      'questionAudioUrl',
      'explanation_audio_url',
      'explanationAudioUrl',
    ]) {
      final v = r[key];
      if (v is String && v.trim().isNotEmpty && !held(v)) {
        return false;
      }
    }
    final options = r['options'];
    if (options is List) {
      for (final o in options.whereType<Map>()) {
        final v = o['image_url'] ?? o['imageUrl'];
        if (v is String && v.trim().isNotEmpty && !held(v)) {
          return false;
        }
      }
    }
    return true;
  }

  final fresh = <Map<String, dynamic>>[];
  final freshButBlind = <Map<String, dynamic>>[];
  final seen = <Map<String, dynamic>>[];
  for (final r in bank) {
    if (recentRank.containsKey(idOf(r))) {
      seen.add(r);
    } else if (picturesHere(r)) {
      fresh.add(r);
    } else {
      freshButBlind.add(r);
    }
  }
  fresh.shuffle(rng);
  freshButBlind.shuffle(rng);
  // Oldest deal first, so the memory rolls through the bank in order
  // rather than re-dealing last round's questions.
  seen.sort((a, b) => recentRank[idOf(a)]!.compareTo(recentRank[idOf(b)]!));

  final picked = <Map<String, dynamic>>[
    ...fresh,
    ...freshButBlind,
    ...seen,
  ].take(n).toList();
  // The round itself is in a random order: "fresh, then the rest"
  // is a rule about WHICH questions, not about where they sit.
  picked.shuffle(rng);
  return picked;
}
