import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/tasks/task_repository.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pausing exactly at UTC+8 midnight queues yesterday and can resume',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime.utc(2026, 10, 8, 15, 50);
      final repo = TaskRepository(database: db, ownerId: 'a', now: () => now);
      await repo.recover(null);
      await repo.start(TaskActivity.language);
      final run = repo.active!.runId;
      now = DateTime.utc(2026, 10, 8, 16);
      await repo.checkpoint(stop: true);
      expect((await repo.records()).single.state, TaskSessionState.ready);
      now = now.add(const Duration(minutes: 5));
      await repo.start(TaskActivity.language, runId: run);
      expect(repo.active!.runId, run);
      expect(repo.active!.runStartedAt, DateTime.utc(2026, 10, 8, 15, 50));
    },
  );
  test(
    'pause excludes idle time; finish queues all segments without photos',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime.utc(2026, 10, 8, 1);
      final repo = TaskRepository(database: db, ownerId: 'a', now: () => now);
      await repo.recover(null);
      await repo.start(TaskActivity.language);
      final first = repo.active!;
      now = now.add(const Duration(minutes: 6));
      await repo.checkpoint(stop: true);
      now = now.add(const Duration(minutes: 20));
      await repo.start(TaskActivity.language, runId: first.runId);
      now = now.add(const Duration(minutes: 5));
      await repo.finishRun(first.runId);
      final records = await repo.records();
      expect(
        records.fold<int>(0, (sum, row) => sum + row.elapsed.inMinutes),
        11,
      );
      expect(
        records.every((row) => row.state == TaskSessionState.ready),
        isTrue,
      );
      expect(records.every((row) => row.photoBytes == null), isTrue);
      expect(records.last.runStartedAt, first.startedAt);
      await expectLater(repo.finishRun(first.runId), completes);
    },
  );

  test(
    'pause cannot reset six-hour wall-clock limit or change activity',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime.utc(2026, 10, 8);
      final repo = TaskRepository(database: db, ownerId: 'a', now: () => now);
      await repo.recover(null);
      await repo.start(TaskActivity.exercise);
      final run = repo.active!.runId;
      now = now.add(const Duration(minutes: 5));
      await repo.checkpoint(stop: true);
      await expectLater(
        repo.start(TaskActivity.language, runId: run),
        throwsStateError,
      );
      now = now.add(const Duration(hours: 6));
      await expectLater(
        repo.start(TaskActivity.exercise, runId: run),
        throwsStateError,
      );
      expect((await repo.records()).single.elapsed.inMinutes, 5);
    },
  );

  test(
    'midnight queues previous date, keeping the same run and new day pending',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime.utc(2026, 10, 8, 15, 54);
      final repo = TaskRepository(database: db, ownerId: 'a', now: () => now);
      await repo.recover(null);
      await repo.start(TaskActivity.language);
      final run = repo.active!.runId;
      now = DateTime.utc(2026, 10, 8, 16, 5);
      await repo.checkpoint();
      final records = await repo.records();
      expect(records.length, 2);
      expect(records.first.state, TaskSessionState.ready);
      expect(records.first.elapsed.inMinutes, 6);
      expect(records.last.elapsed.inMinutes, 5);
      expect(repo.active!.runId, run);
      expect(repo.active!.startedAt, DateTime.utc(2026, 10, 8, 16));
    },
  );
}
