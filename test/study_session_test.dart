import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/study/study_session.dart';

void main() {
  final start = DateTime.utc(2026, 9, 26, 15, 59);
  StudySession session() => StudySession(
    id: 's',
    ownerId: 'a',
    startedAt: start,
    recordedUntil: start,
    state: StudySessionState.running,
  );
  test('six-hour limit does not reset across Beijing midnight', () {
    final end = session().checkpoint(start.add(const Duration(hours: 7)));
    expect(end.elapsed, const Duration(hours: 6));
    expect(end.state, StudySessionState.pendingConfirmation);
  });
  test('cold recovery uses durable evidence without adding shutdown time', () {
    final saved = session().checkpoint(start.add(const Duration(seconds: 45)));
    final restored = saved.recover().checkpoint(
      start.add(const Duration(days: 1)),
    );
    expect(restored.elapsed, const Duration(seconds: 45));
    expect(restored.state, StudySessionState.pendingConfirmation);
  });
  test('backwards clock never subtracts persisted time', () {
    final saved = session().checkpoint(start.add(const Duration(seconds: 45)));
    expect(saved.checkpoint(start).elapsed, saved.elapsed);
  });
}
