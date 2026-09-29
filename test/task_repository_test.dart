import 'dart:typed_data';

import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/study/study_session.dart';
import 'package:cat_library_demo/features/tasks/task_repository.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'interrupted task keeps last checkpoint and needs a photo before queueing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime.utc(2026, 9, 26);
      final repo = TaskRepository(database: db, ownerId: 'a', now: () => now);
      await repo.recover(null);
      await repo.start(TaskActivity.language);
      final id = repo.active!.id;
      now = now.add(const Duration(minutes: 6));
      await repo.checkpoint();
      final restarted = TaskRepository(
        database: db,
        ownerId: 'a',
        now: () => now.add(const Duration(days: 1)),
      );
      await restarted.recover(
        StudySession(
          id: id,
          ownerId: 'a',
          startedAt: DateTime.utc(2026, 9, 26),
          recordedUntil: now.add(const Duration(minutes: 1)),
          state: StudySessionState.running,
        ),
      );
      var record = (await restarted.records()).single;
      expect(record.elapsed, const Duration(minutes: 7));
      expect(record.state, TaskSessionState.pendingPhoto);
      await expectLater(restarted.confirm(id), throwsStateError);
      await restarted.attachPhoto(
        id,
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      );
      await restarted.confirm(id);
      record = (await restarted.records()).single;
      expect(record.state, TaskSessionState.ready);
      expect(record.photoMime, 'image/jpeg');
      await db.acknowledgeTask('a', id);
      record = (await restarted.records()).single;
      expect(record.state, TaskSessionState.synced);
      expect(record.photoBytes, isNull);
    },
  );

  test('pending exchange keeps its request id across reopen', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.queueExchange('a', 'request-1', 'eagle');
    expect(await db.pendingExchange('a'), ('request-1', 'eagle'));
    await db.acknowledgeExchange('a', 'request-1');
    expect(await db.pendingExchange('a'), isNull);
  });
}
