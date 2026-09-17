import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/time/study_clock.dart';

void main() {
  final start = DateTime.utc(2026, 9, 17, 15, 59);
  test('UTC+8 midnight splits seconds without rounding or rewards', () {
    final probe = StudyClock(start)
      ..checkpoint(start.add(const Duration(minutes: 2)));
    expect(probe.secondsByDay, {'2026-09-17': 60, '2026-09-18': 60});
  });
  test('cold recovery ends at durable checkpoint, not reopen time', () {
    final probe = StudyClock(start)
      ..checkpoint(start.add(const Duration(seconds: 30)));
    final recovered = StudyClock.restore(probe.toJson());
    expect(recovered.running, false);
    recovered.checkpoint(start.add(const Duration(hours: 5)));
    expect(recovered.elapsed.inSeconds, 30);
  });
  test('warm resume caps the whole session at six hours across midnight', () {
    final probe = StudyClock(start)
      ..checkpoint(start.add(const Duration(hours: 7)));
    expect(probe.elapsed, const Duration(hours: 6));
    expect(probe.running, false);
    expect(probe.secondsByDay.values.reduce((a, b) => a + b), 21600);
  });
  test('clock reversal cannot subtract already recorded time', () {
    final probe = StudyClock(start)
      ..checkpoint(start.add(const Duration(minutes: 2)));
    probe.checkpoint(start.subtract(const Duration(minutes: 2)));
    expect(probe.elapsed.inSeconds, 120);
    expect(probe.clockReversed, true);
  });
  test('ending is stable across repeated callbacks', () {
    final probe = StudyClock(start)
      ..stop(start.add(const Duration(seconds: 59)));
    probe.checkpoint(start.add(const Duration(minutes: 10)));
    expect(probe.elapsed.inSeconds, 59);
    expect(StudyClock.restore(probe.toJson()).elapsed.inSeconds, 59);
  });
}
