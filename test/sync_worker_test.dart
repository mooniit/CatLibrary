import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/core/sync/sync_worker.dart';
import 'package:cat_library_demo/features/study/study_session.dart';

void main() {
  test(
    'lost server response retries the identical record; another owner stays queued',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final start = DateTime.utc(2026, 9, 26);
      for (final owner in ['a', 'b']) {
        final session = StudySession(
          id: owner,
          ownerId: owner,
          startedAt: start,
          recordedUntil: start,
          state: StudySessionState.running,
        );
        await db.start(session);
        await db.checkpoint(
          session.checkpoint(
            start.add(const Duration(minutes: 10)),
            stop: true,
          ),
        );
        await db.confirm(owner, owner, start);
      }
      final received = <String>[];
      var loseResponse = true;
      final worker = StudySyncWorker(
        database: db,
        ownerId: 'a',
        submit: (record) async {
          received.add(
            '${record.id}:${record.recordedUntil.toIso8601String()}',
          );
          if (loseResponse) {
            throw StateError('Response lost after server commit');
          }
        },
      );
      await expectLater(worker.sync(), throwsStateError);
      expect((await db.sessions('a')).single.state, StudySessionState.queued);
      loseResponse = false;
      await Future.wait([worker.sync(), worker.sync()]);
      expect(received, hasLength(2));
      expect(received.first, received.last);
      expect((await db.sessions('a')).single.state, StudySessionState.synced);
      expect((await db.sessions('b')).single.state, StudySessionState.queued);
    },
  );
}
