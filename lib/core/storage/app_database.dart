import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/study/study_session.dart';

/// Formal records are separate from M0's experimental checkpoint database.
class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'cat_library'));

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''CREATE TABLE study_sessions (
      id TEXT PRIMARY KEY, owner_id TEXT NOT NULL,
      started_ms INTEGER NOT NULL, recorded_ms INTEGER NOT NULL,
      state TEXT NOT NULL CHECK(state IN
        ('running','pendingConfirmation','queued','synced')),
      CHECK(recorded_ms >= started_ms AND recorded_ms - started_ms <= 21600000)
    )''');
      await customStatement(
        "CREATE UNIQUE INDEX one_running_study ON study_sessions(owner_id) WHERE state = 'running'",
      );
      await customStatement('''CREATE TABLE pending_operations (
      session_id TEXT PRIMARY KEY REFERENCES study_sessions(id),
      owner_id TEXT NOT NULL, created_ms INTEGER NOT NULL
    )''');
    },
  );

  Future<List<StudySession>> sessions(
    String ownerId,
  ) async => (await customSelect(
    'SELECT * FROM study_sessions WHERE owner_id = ? ORDER BY started_ms, id',
    variables: [Variable(ownerId)],
  ).get()).map(_session).toList();

  static StudySession _session(QueryRow row) => StudySession(
    id: row.read<String>('id'),
    ownerId: row.read<String>('owner_id'),
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('started_ms'),
      isUtc: true,
    ),
    recordedUntil: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('recorded_ms'),
      isUtc: true,
    ),
    state: StudySessionState.values.byName(row.read<String>('state')),
  );

  Future<void> start(StudySession session) => transaction(() async {
    if (session.state != StudySessionState.running ||
        session.elapsed != Duration.zero) {
      throw StateError('A session must start with zero recorded duration');
    }
    final overlap = await customSelect(
      '''SELECT id FROM study_sessions
      WHERE owner_id = ? AND (state = 'running' OR recorded_ms > ?) LIMIT 1''',
      variables: [
        Variable(session.ownerId),
        Variable(session.startedAt.millisecondsSinceEpoch),
      ],
    ).getSingleOrNull();
    if (overlap != null) throw StateError('Overlapping study session');
    await customStatement('INSERT INTO study_sessions VALUES (?, ?, ?, ?, ?)', [
      session.id,
      session.ownerId,
      session.startedAt.millisecondsSinceEpoch,
      session.recordedUntil.millisecondsSinceEpoch,
      session.state.name,
    ]);
  });

  Future<void> checkpoint(StudySession session) async {
    if (session.state != StudySessionState.running &&
        session.state != StudySessionState.pendingConfirmation) {
      throw StateError('Use confirm to queue a session');
    }
    final count = await customUpdate(
      '''UPDATE study_sessions SET recorded_ms = ?, state = ?
      WHERE id = ? AND owner_id = ? AND started_ms = ? AND state = 'running'
      AND recorded_ms <= ?''',
      variables: [
        Variable(session.recordedUntil.millisecondsSinceEpoch),
        Variable(session.state.name),
        Variable(session.id),
        Variable(session.ownerId),
        Variable(session.startedAt.millisecondsSinceEpoch),
        Variable(session.recordedUntil.millisecondsSinceEpoch),
      ],
      updates: {},
    );
    if (count != 1) {
      throw StateError('Checkpoint no longer matches active session');
    }
  }

  Future<void> recover(String ownerId) => customStatement(
    "UPDATE study_sessions SET state = 'pendingConfirmation' WHERE owner_id = ? AND state = 'running'",
    [ownerId],
  );

  /// Confirmation and the retry queue commit together, including after restart.
  Future<void> confirm(
    String ownerId,
    String id,
    DateTime now,
  ) => transaction(() async {
    final rows = await sessions(ownerId);
    final session = rows.where((s) => s.id == id).firstOrNull;
    if (session == null || session.state == StudySessionState.running) {
      throw StateError('No stopped session to confirm');
    }
    if (session.state != StudySessionState.pendingConfirmation) return;
    await customStatement(
      "UPDATE study_sessions SET state = 'queued' WHERE id = ? AND owner_id = ?",
      [id, ownerId],
    );
    await customStatement('INSERT INTO pending_operations VALUES (?, ?, ?)', [
      id,
      ownerId,
      now.toUtc().millisecondsSinceEpoch,
    ]);
  });

  Future<void> acknowledge(String ownerId, String id) => transaction(() async {
    await customStatement(
      "UPDATE study_sessions SET state = 'synced' WHERE id = ? AND owner_id = ? AND state = 'queued'",
      [id, ownerId],
    );
    await customStatement(
      'DELETE FROM pending_operations WHERE session_id = ? AND owner_id = ?',
      [id, ownerId],
    );
  });
}
