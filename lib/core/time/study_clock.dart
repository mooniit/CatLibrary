import 'dart:convert';

/// T03 probe: UTC timestamps and raw seconds only, never a currency calculator.
class StudyClock {
  StudyClock(DateTime start)
    : startedAt = start.toUtc(),
      recordedUntil = start.toUtc();
  final DateTime startedAt;
  DateTime recordedUntil;
  bool running = true;
  bool clockReversed = false;
  Duration get elapsed => recordedUntil.difference(startedAt);
  void checkpoint(DateTime now) {
    if (!running) return;
    final utc = now.toUtc();
    if (utc.isBefore(recordedUntil)) {
      clockReversed = true;
      return;
    }
    final limit = startedAt.add(const Duration(hours: 6));
    recordedUntil = utc.isAfter(limit) ? limit : utc;
    if (!utc.isBefore(limit)) running = false;
  }

  void stop(DateTime now) {
    checkpoint(now);
    running = false;
  }

  Map<String, int> get secondsByDay {
    final result = <String, int>{};
    var cursor = startedAt;
    while (cursor.isBefore(recordedUntil)) {
      final shifted = cursor.add(const Duration(hours: 8));
      final day = shifted.toIso8601String().substring(0, 10);
      final midnight = DateTime.utc(
        shifted.year,
        shifted.month,
        shifted.day + 1,
      ).subtract(const Duration(hours: 8));
      final end = recordedUntil.isBefore(midnight) ? recordedUntil : midnight;
      result[day] = end.difference(cursor).inSeconds;
      cursor = end;
    }
    return result;
  }

  String toJson() => jsonEncode({
    'start': startedAt.toIso8601String(),
    'checkpoint': recordedUntil.toIso8601String(),
    'running': running,
  });
  factory StudyClock.restore(String raw) {
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final probe = StudyClock(DateTime.parse(value['start'] as String));
    final end = DateTime.parse(value['checkpoint'] as String).toUtc();
    if (end.isBefore(probe.startedAt) ||
        end.difference(probe.startedAt) > const Duration(hours: 6)) {
      throw const FormatException('Invalid checkpoint');
    }
    probe.recordedUntil = end;
    // Cold start has no evidence for time after the last durable checkpoint.
    probe.running = false;
    return probe;
  }
}
