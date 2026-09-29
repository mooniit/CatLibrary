import 'dart:typed_data';

import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/tasks/weekly_tasks.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sunday = DateTime.utc(2026, 9, 27, 12);
  Map<String, dynamic> offer(String id, String kind, int count) => {
    'offer_id': id,
    'task_id': id,
    'prompt': '任务 $id',
    'evidence_kind': kind,
    'image_count': count,
    'week_start': '2026-09-21',
    'confirmed_at': null,
  };

  test(
    'Sunday offline confirmation survives Monday and keeps both photos',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.saveWeeklyOffers('a', [offer('old', 'photo', 2)]);
      final repo = WeeklyRepository(db, 'a');
      final task = (await repo.cachedTasks()).single;
      await expectLater(repo.confirm(task, sunday), throwsStateError);
      final photo = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
      await repo.savePhoto(task, 0, photo);
      await expectLater(repo.confirm(task, sunday), throwsStateError);
      await repo.savePhoto(task, 1, photo);
      await repo.confirm(task, sunday);
      await expectLater(repo.confirm(task, sunday), throwsStateError);
      final persisted = (await WeeklyRepository(db, 'a').drafts()).single;
      expect(persisted.state, 'ready');
      expect(persisted.confirmedAt, sunday);
      expect(persisted.photos[0], photo);
      expect(persisted.photos[1], photo);
      await db.saveWeeklyOffers('a', [
        offer('old', 'photo', 2),
        offer('new', 'self', 0),
      ]);
      expect((await repo.cachedTasks()).map((t) => t.offerId), ['old', 'new']);
      await db.acknowledgeWeekly('a', 'old');
      expect((await repo.drafts()).single.photos, [null, null]);
    },
  );

  test('text evidence is required and limited to 100 characters', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.saveWeeklyOffers('a', [offer('text', 'text', 0)]);
    final repo = WeeklyRepository(db, 'a');
    final task = (await repo.cachedTasks()).single;
    await expectLater(repo.confirm(task, sunday), throwsStateError);
    await expectLater(repo.saveNote(task, 'x' * 101), throwsArgumentError);
    await repo.saveNote(task, '完成了一次辩论');
    await repo.confirm(task, sunday);
    expect((await repo.drafts()).single.note, '完成了一次辩论');
  });
}
