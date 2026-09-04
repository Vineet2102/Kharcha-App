import 'dart:math';

/// Transient-failure retry delay (spec §9.6 pushOutbox()):
/// `min(2^attempts seconds, 15 minutes)` with ±20% jitter, so multiple
/// devices that failed at the same instant don't all retry in lockstep.
///
/// [attempts] is the count *after* incrementing for this failure (i.e. the
/// first failure passes `attempts: 1`). [random] is injectable for
/// deterministic tests.
Duration computeBackoff(int attempts, {Random? random}) {
  assert(attempts >= 1, 'attempts must be >= 1');
  final rand = random ?? Random();
  const cap = Duration(minutes: 15);

  final baseSeconds = attempts >= 31
      ? cap.inSeconds
      : min(pow(2, attempts).toInt(), cap.inSeconds);
  final jitterFraction = 1 + (rand.nextDouble() * 0.4 - 0.2); // ±20%
  final jitteredSeconds = (baseSeconds * jitterFraction).round();

  return Duration(seconds: jitteredSeconds.clamp(0, cap.inSeconds));
}
