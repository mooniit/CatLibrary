import 'dart:io';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class LegacyTaskDatabase extends AppDatabase {
  LegacyTaskDatabase(super.executor);
  @override
  int get schemaVersion => 8;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''CREATE TABLE task_sessions (
      id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, activity TEXT NOT NULL,
      started_ms INTEGER NOT NULL, recorded_ms INTEGER NOT NULL, state TEXT NOT NULL,
      photo_bytes BLOB, photo_mime TEXT)''');
    },
  );
}

void main() {
  test(
    'v8 upgrade preserves historical photos and unconfirmed checkpoints',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cat-task-upgrade-',
      );
      final file = File('${directory.path}/tasks.sqlite');
      final old = LegacyTaskDatabase(NativeDatabase(file));
      await old.customStatement(
        "INSERT INTO task_sessions VALUES ('old','a','language',0,360000,'pendingPhoto',X'FFD8FFD9','image/jpeg')",
      );
      await old.close();
      final db = AppDatabase(NativeDatabase(file));
      try {
        final record = (await db.taskSessions('a')).single;
        expect(record.state, TaskSessionState.pendingPhoto);
        expect(record.elapsed.inMinutes, 6);
        expect(record.runId, 'old');
        expect(record.runStartedAt, record.startedAt);
        expect(record.photoBytes, [255, 216, 255, 217]);
        expect(await db.cachedTaskFeed('a'), isEmpty);
      } finally {
        await db.close();
        await file.delete();
        await directory.delete();
      }
    },
  );
}
