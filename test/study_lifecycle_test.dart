import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/study/study_repository.dart';
import 'package:cat_library_demo/features/study/study_session.dart';
import 'package:cat_library_demo/features/study/study_reward.dart';

void main() {
  test('daily remainder pays only the difference and stops at 120', () {
    expect(remainingStudyCoins(const Duration(minutes: 5, seconds: 30), 0), 10);
    expect(
      remainingStudyCoins(const Duration(minutes: 11, seconds: 10), 10),
      12,
    );
    expect(
      remainingStudyCoins(const Duration(minutes: 11, seconds: 10), 22),
      0,
    );
    expect(remainingStudyCoins(const Duration(minutes: 61), 118), 2);
    expect(remainingStudyCoins(const Duration(hours: 6), 120), 0);
  });
  test(
    'native durable checkpoint extends SQLite recovery, never shutdown time',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final start = DateTime.utc(2026, 9, 26);
      final record = StudySession(
        id: 'native',
        ownerId: 'a',
        startedAt: start,
        recordedUntil: start,
        state: StudySessionState.running,
      );
      await db.start(record);
      await db.checkpoint(
        record.checkpoint(start.add(const Duration(seconds: 10))),
      );
      final repo = StudyRepository(
        database: db,
        ownerId: 'a',
        now: () => start.add(const Duration(days: 1)),
      );
      await repo.recover(
        durableNative: record.checkpoint(start.add(const Duration(minutes: 2))),
      );
      final recovered = (await repo.records()).single;
      expect(recovered.elapsed, const Duration(minutes: 2));
      expect(recovered.state, StudySessionState.pendingConfirmation);
      await repo.recover(
        durableNative: record.checkpoint(start.add(const Duration(minutes: 4))),
      );
      expect((await repo.records()).single.elapsed, const Duration(minutes: 2));
    },
  );
  test(
    'wallet cache is identity scoped and cannot be replaced by another owner',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final snapshot = {
        'wallet': {
          'owner_id': 'a',
          'miao_coins': 52,
          'eagle_pounds': 0,
          'gems': 0,
        },
        'days': [],
      };
      await db.saveAccountSnapshot('a', snapshot);
      expect(await db.accountSnapshot('a'), snapshot);
      expect(await db.accountSnapshot('b'), isNull);
      expect(() => db.saveAccountSnapshot('b', snapshot), throwsStateError);
    },
  );
}
