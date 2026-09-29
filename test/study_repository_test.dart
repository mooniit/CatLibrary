import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/study/study_repository.dart';
import 'package:cat_library_demo/features/study/study_session.dart';

void main() {
  test(
    'preset example seeds once per owner and hour cap is enforced',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect((await db.presets('a')).single.name, '示例');
      expect((await db.presets('a')).single.seconds, 2400);
      await db.deletePreset('a', 2400);
      expect(await db.presets('a'), isEmpty);
      expect((await db.presets('b')).single.name, '示例');
      await db.addPreset('a', 21599, '最长设置');
      expect((await db.presets('a')).single.seconds, 21599);
      await expectLater(db.addPreset('a', 21600, '超限'), throwsArgumentError);
    },
  );

  test('paused intervals preserve one run identity in SQLite', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var time = DateTime.utc(2026, 9, 26);
    final repo = StudyRepository(database: db, ownerId: 'a', now: () => time);
    await repo.recover();
    await repo.start();
    final runId = repo.active!.runId;
    time = time.add(const Duration(minutes: 5));
    await repo.checkpoint(stop: true);
    time = time.add(const Duration(minutes: 10));
    await repo.start(runId: runId);
    time = time.add(const Duration(minutes: 5));
    await repo.checkpoint(stop: true);
    final saved = await db.sessions('a');
    expect(saved.map((record) => record.runId).toSet(), {runId});
    expect(
      saved.fold<int>(0, (sum, record) => sum + record.elapsed.inMinutes),
      10,
    );
  });

  test(
    'multiple offline sessions survive recovery and retain distinct IDs',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var time = DateTime.utc(2026, 9, 26);
      final repo = StudyRepository(database: db, ownerId: 'a', now: () => time);
      await repo.recover();
      for (var i = 0; i < 3; i++) {
        await repo.start();
        time = time.add(const Duration(minutes: 11));
        await repo.checkpoint(stop: true);
      }
      final records = await repo.records();
      expect(records.map((r) => r.id).toSet(), hasLength(3));
      for (final record in records) {
        await repo.confirm(record.id);
      }
      final fresh = StudyRepository(
        database: db,
        ownerId: 'a',
        now: () => time,
      );
      await fresh.recover();
      expect(
        (await fresh.records()).every(
          (r) => r.state == StudySessionState.queued,
        ),
        isTrue,
      );
    },
  );
  test(
    'interrupted write stops in-memory timer and recovers last committed evidence',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var time = DateTime.utc(2026, 9, 26);
      final repo = StudyRepository(database: db, ownerId: 'a', now: () => time);
      await repo.recover();
      await repo.start();
      time = time.add(const Duration(seconds: 20));
      await repo.checkpoint();
      await db.customStatement(
        "CREATE TRIGGER fail_checkpoint BEFORE UPDATE ON study_sessions BEGIN SELECT RAISE(ABORT, 'disk fault'); END",
      );
      time = time.add(const Duration(minutes: 20));
      await expectLater(repo.checkpoint(), throwsA(isA<Exception>()));
      expect(repo.active, isNull);
      expect(repo.needsRecovery, isTrue);
      await expectLater(repo.start(), throwsStateError);
      await db.customStatement('DROP TRIGGER fail_checkpoint');
      await repo.recover();
      final record = (await repo.records()).single;
      expect(record.elapsed, const Duration(seconds: 20));
      expect(record.state, StudySessionState.pendingConfirmation);
    },
  );
}
