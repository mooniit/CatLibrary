import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/study/study_session.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26);
  StudySession session(String id, {String owner = 'a'}) => StudySession(
    id: id,
    ownerId: owner,
    startedAt: now,
    recordedUntil: now,
    state: StudySessionState.running,
  );
  test('one running record; stopped intervals cannot overlap', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.start(session('one'));
    await expectLater(db.start(session('two')), throwsStateError);
    await db.checkpoint(
      session(
        'one',
      ).checkpoint(now.add(const Duration(minutes: 2)), stop: true),
    );
    await expectLater(db.start(session('two')), throwsStateError);
    await db.start(session('other', owner: 'b'));
    expect(await db.sessions('a'), hasLength(1));
  });
  test(
    'reopen preserves evidence and confirmation queue exactly once',
    () async {
      final dir = await Directory.systemTemp.createTemp('cat_study_');
      final file = File('${dir.path}/study.sqlite');
      final db = AppDatabase(NativeDatabase(file));
      await db.start(session('one'));
      await db.checkpoint(
        session('one').checkpoint(now.add(const Duration(minutes: 11))),
      );
      await db.close();
      final reopened = AppDatabase(NativeDatabase(file));
      try {
        await reopened.recover('a');
        final recovered = (await reopened.sessions('a')).single;
        expect(recovered.elapsed, const Duration(minutes: 11));
        expect(recovered.state, StudySessionState.pendingConfirmation);
        await reopened.confirm('a', 'one', now);
        await reopened.confirm('a', 'one', now);
        expect(
          await reopened.customSelect('SELECT * FROM pending_operations').get(),
          hasLength(1),
        );
        await reopened.acknowledge('b', 'one');
        expect(
          (await reopened.sessions('a')).single.state,
          StudySessionState.queued,
        );
        await reopened.acknowledge('a', 'one');
        expect(
          (await reopened.sessions('a')).single.state,
          StudySessionState.synced,
        );
        expect(
          await reopened.customSelect('SELECT * FROM pending_operations').get(),
          isEmpty,
        );
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('failure inserting an outbox item rolls back confirmation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.start(session('one'));
    await db.checkpoint(
      session(
        'one',
      ).checkpoint(now.add(const Duration(minutes: 10)), stop: true),
    );
    await db.customStatement(
      "CREATE TRIGGER fail_queue BEFORE INSERT ON pending_operations BEGIN SELECT RAISE(ABORT, 'queue unavailable'); END",
    );
    await expectLater(db.confirm('a', 'one', now), throwsA(isA<Exception>()));
    expect(
      (await db.sessions('a')).single.state,
      StudySessionState.pendingConfirmation,
    );
    expect(
      await db.customSelect('SELECT * FROM pending_operations').get(),
      isEmpty,
    );
    await db.customStatement('DROP TRIGGER fail_queue');
    await db.confirm('a', 'one', now);
    expect((await db.sessions('a')).single.state, StudySessionState.queued);
  });
}
