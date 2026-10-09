import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/study/study_session.dart';
import '../../features/tasks/task_session.dart';

class StudyPreset {
  const StudyPreset(this.seconds, this.name);
  final int seconds;
  final String name;
}

class WeeklyDraft {
  const WeeklyDraft(
    this.offerId,
    this.note,
    this.photos,
    this.mimes,
    this.state,
    this.confirmedAt,
  );
  final String offerId, note, state;
  final List<Uint8List?> photos;
  final List<String?> mimes;
  final DateTime? confirmedAt;
}

/// Formal records are separate from M0's experimental checkpoint database.
class AppDatabase extends GeneratedDatabase {
  static final AppDatabase shared = AppDatabase();
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'cat_library'));

  @override
  int get schemaVersion => 9;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (_, from, to) async {
      if (from < 2) await _createCache();
      if (from < 3) {
        await customStatement(
          'ALTER TABLE study_sessions ADD COLUMN run_id TEXT',
        );
        await customStatement('UPDATE study_sessions SET run_id = id');
        await _createPresets();
      }
      if (from < 4) await _createTasks();
      if (from < 5) await _createExchanges();
      if (from < 6) await _createWeekly();
      if (from < 7) await _createFurniture();
      if (from >= 5 && from < 8) {
        await customStatement(
          'ALTER TABLE pending_exchanges ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1',
        );
      }
      if (from >= 4 && from < 9) {
        await customStatement(
          'ALTER TABLE task_sessions ADD COLUMN run_id TEXT',
        );
        await customStatement(
          'ALTER TABLE task_sessions ADD COLUMN run_started_ms INTEGER',
        );
        await customStatement(
          'UPDATE task_sessions SET run_id=id, run_started_ms=started_ms',
        );
      }
      if (from < 9) await _createTaskFeed();
    },
    onCreate: (_) async {
      await _createCache();
      await customStatement('''CREATE TABLE study_sessions (
      id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, run_id TEXT NOT NULL,
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
      await _createPresets();
      await _createTasks();
      await _createTaskFeed();
      await _createExchanges();
      await _createWeekly();
      await _createFurniture();
    },
  );

  Future<void> _createCache() => customStatement(
    'CREATE TABLE account_cache (owner_id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
  );

  Future<void> _createFurniture() =>
      customStatement('''CREATE TABLE furniture_local (
    owner_id TEXT NOT NULL, family_id TEXT NOT NULL, kind TEXT NOT NULL,
    payload TEXT NOT NULL, PRIMARY KEY(owner_id,family_id,kind)
  )''');

  Future<Map<String, dynamic>?> furnitureLocal(
    String ownerId,
    String familyId,
    String kind,
  ) async {
    final row = await customSelect(
      'SELECT payload FROM furniture_local WHERE owner_id=? AND family_id=? AND kind=?',
      variables: [Variable(ownerId), Variable(familyId), Variable(kind)],
    ).getSingleOrNull();
    return row == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(row.read<String>('payload')));
  }

  Future<void> putFurnitureLocal(
    String ownerId,
    String familyId,
    String kind,
    Map<String, dynamic> payload,
  ) => customStatement(
    '''INSERT INTO furniture_local VALUES (?,?,?,?)
      ON CONFLICT(owner_id,family_id,kind) DO UPDATE SET payload=excluded.payload''',
    [ownerId, familyId, kind, jsonEncode(payload)],
  );

  Future<void> removeFurnitureLocal(
    String ownerId,
    String familyId,
    String kind,
  ) => customStatement(
    'DELETE FROM furniture_local WHERE owner_id=? AND family_id=? AND kind=?',
    [ownerId, familyId, kind],
  );

  Future<void> _createPresets() async {
    await customStatement('''CREATE TABLE study_presets (
      owner_id TEXT NOT NULL, seconds INTEGER NOT NULL CHECK(seconds BETWEEN 1 AND 21599),
      name TEXT NOT NULL, PRIMARY KEY(owner_id, seconds)
    )''');
    await customStatement(
      'CREATE TABLE study_preset_owners (owner_id TEXT PRIMARY KEY)',
    );
  }

  Future<void> _createTasks() async {
    await customStatement('''CREATE TABLE task_sessions (
      id TEXT PRIMARY KEY, owner_id TEXT NOT NULL,
      activity TEXT NOT NULL CHECK(activity IN ('language','exercise')),
      started_ms INTEGER NOT NULL, recorded_ms INTEGER NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('running','pendingPhoto','ready','synced')),
      photo_bytes BLOB, photo_mime TEXT,
      run_id TEXT, run_started_ms INTEGER,
      CHECK(recorded_ms >= started_ms AND recorded_ms - started_ms <= 21600000)
    )''');
    await customStatement(
      "CREATE UNIQUE INDEX one_running_task ON task_sessions(owner_id) WHERE state = 'running'",
    );
  }

  Future<void> _createExchanges() =>
      customStatement('''CREATE TABLE pending_exchanges (
    owner_id TEXT PRIMARY KEY, request_id TEXT NOT NULL UNIQUE,
    currency TEXT NOT NULL CHECK(currency IN ('eagle','gem')),
    quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0)
  )''');

  Future<void> _createTaskFeed() => customStatement(
    'CREATE TABLE task_feed_cache (owner_id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
  );
  Future<List<Map<String, dynamic>>> cachedTaskFeed(String ownerId) async {
    final row = await customSelect(
      'SELECT payload FROM task_feed_cache WHERE owner_id=?',
      variables: [Variable(ownerId)],
    ).getSingleOrNull();
    if (row == null) return [];
    return [
      for (final item in jsonDecode(row.read<String>('payload')) as List)
        Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<void> cacheTaskFeed(
    String ownerId,
    List<Map<String, dynamic>> feed,
  ) => customStatement(
    'INSERT INTO task_feed_cache VALUES (?,?) ON CONFLICT(owner_id) DO UPDATE SET payload=excluded.payload',
    [ownerId, jsonEncode(feed)],
  );

  Future<void> _createWeekly() async {
    await customStatement('''CREATE TABLE weekly_offer_cache (
      owner_id TEXT PRIMARY KEY, payload TEXT NOT NULL
    )''');
    await customStatement('''CREATE TABLE weekly_drafts (
      offer_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '', photo0 BLOB, mime0 TEXT,
      photo1 BLOB, mime1 TEXT,
      state TEXT NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','ready','synced')),
      confirmed_ms INTEGER
    )''');
  }

  Future<List<Map<String, dynamic>>> weeklyOffers(String ownerId) async {
    final row = await customSelect(
      'SELECT payload FROM weekly_offer_cache WHERE owner_id=?',
      variables: [Variable(ownerId)],
    ).getSingleOrNull();
    return row == null
        ? []
        : [
            for (final item in jsonDecode(row.read<String>('payload')) as List)
              Map<String, dynamic>.from(item as Map),
          ];
  }

  Future<void> saveWeeklyOffers(
    String ownerId,
    List<Map<String, dynamic>> items,
  ) => customStatement(
    '''INSERT INTO weekly_offer_cache VALUES (?,?)
      ON CONFLICT(owner_id) DO UPDATE SET payload=excluded.payload''',
    [ownerId, jsonEncode(items)],
  );

  Future<List<WeeklyDraft>> weeklyDrafts(String ownerId) async => [
    for (final row in await customSelect(
      'SELECT * FROM weekly_drafts WHERE owner_id=?',
      variables: [Variable(ownerId)],
    ).get())
      WeeklyDraft(
        row.read<String>('offer_id'),
        row.read<String>('note'),
        [
          row.readNullable<Uint8List>('photo0'),
          row.readNullable<Uint8List>('photo1'),
        ],
        [row.readNullable<String>('mime0'), row.readNullable<String>('mime1')],
        row.read<String>('state'),
        switch (row.readNullable<int>('confirmed_ms')) {
          final int value => DateTime.fromMillisecondsSinceEpoch(
            value,
            isUtc: true,
          ),
          null => null,
        },
      ),
  ];

  Future<void> saveWeeklyNote(
    String ownerId,
    String offerId,
    String note,
  ) async {
    if (note.length > 100) throw ArgumentError('Weekly note is too long');
    await customStatement(
      '''INSERT INTO weekly_drafts(offer_id,owner_id,note)
      VALUES (?,?,?) ON CONFLICT(offer_id) DO UPDATE SET note=excluded.note
      WHERE weekly_drafts.owner_id=excluded.owner_id AND weekly_drafts.state='draft' ''',
      [offerId, ownerId, note],
    );
  }

  Future<void> saveWeeklyPhoto(
    String ownerId,
    String offerId,
    int slot,
    Uint8List bytes,
  ) async {
    if (slot < 0 || slot > 1 || bytes.length < 4 || bytes.length > 5242880) {
      throw ArgumentError('Invalid weekly photo');
    }
    final mime = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff
        ? 'image/jpeg'
        : bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4e &&
              bytes[3] == 0x47
        ? 'image/png'
        : null;
    if (mime == null) throw ArgumentError('Only JPEG or PNG are supported');
    await customStatement(
      'INSERT INTO weekly_drafts(offer_id,owner_id) VALUES (?,?) ON CONFLICT DO NOTHING',
      [offerId, ownerId],
    );
    final count = await customUpdate(
      'UPDATE weekly_drafts SET photo$slot=?,mime$slot=? WHERE offer_id=? AND owner_id=? AND state=\'draft\'',
      variables: [
        Variable(bytes),
        Variable(mime),
        Variable(offerId),
        Variable(ownerId),
      ],
      updates: {},
    );
    if (count != 1) throw StateError('Weekly draft cannot be edited');
  }

  Future<void> queueWeekly(
    String ownerId,
    String offerId,
    DateTime confirmedAt,
  ) async {
    await customStatement(
      'INSERT INTO weekly_drafts(offer_id,owner_id) VALUES (?,?) ON CONFLICT DO NOTHING',
      [offerId, ownerId],
    );
    final count = await customUpdate(
      "UPDATE weekly_drafts SET state='ready',confirmed_ms=? WHERE offer_id=? AND owner_id=? AND state='draft'",
      variables: [
        Variable(confirmedAt.toUtc().millisecondsSinceEpoch),
        Variable(offerId),
        Variable(ownerId),
      ],
      updates: {},
    );
    if (count != 1) throw StateError('Weekly completion already queued');
  }

  Future<void> acknowledgeWeekly(
    String ownerId,
    String offerId,
  ) => customStatement(
    "UPDATE weekly_drafts SET state='synced',photo0=NULL,photo1=NULL WHERE offer_id=? AND owner_id=? AND state='ready'",
    [offerId, ownerId],
  );

  Future<(String, String, int)?> pendingExchange(String ownerId) async {
    final row = await customSelect(
      'SELECT request_id,currency,quantity FROM pending_exchanges WHERE owner_id=?',
      variables: [Variable(ownerId)],
    ).getSingleOrNull();
    return row == null
        ? null
        : (
            row.read<String>('request_id'),
            row.read<String>('currency'),
            row.read<int>('quantity'),
          );
  }

  Future<void> queueExchange(
    String ownerId,
    String requestId,
    String currency, [
    int quantity = 1,
  ]) => customStatement(
    'INSERT INTO pending_exchanges(owner_id,request_id,currency,quantity) VALUES (?,?,?,?)',
    [ownerId, requestId, currency, quantity],
  );

  Future<void> acknowledgeExchange(String ownerId, String requestId) =>
      customStatement(
        'DELETE FROM pending_exchanges WHERE owner_id=? AND request_id=?',
        [ownerId, requestId],
      );

  /// Seed once per identity, so deleting the example does not recreate it.
  Future<List<StudyPreset>> presets(String ownerId) => transaction(() async {
    final initialized = await customSelect(
      'SELECT 1 FROM study_preset_owners WHERE owner_id = ?',
      variables: [Variable(ownerId)],
    ).getSingleOrNull();
    if (initialized == null) {
      await customStatement('INSERT INTO study_preset_owners VALUES (?)', [
        ownerId,
      ]);
      await customStatement('INSERT INTO study_presets VALUES (?, ?, ?)', [
        ownerId,
        2400,
        '示例',
      ]);
    }
    final rows = await customSelect(
      'SELECT seconds, name FROM study_presets WHERE owner_id = ? ORDER BY seconds',
      variables: [Variable(ownerId)],
    ).get();
    return [
      for (final row in rows)
        StudyPreset(row.read<int>('seconds'), row.read<String>('name')),
    ];
  });

  Future<void> addPreset(String ownerId, int seconds, String name) async {
    final trimmed = name.trim();
    if (seconds < 1 ||
        seconds > 21599 ||
        trimmed.isEmpty ||
        trimmed.length > 24) {
      throw ArgumentError('Invalid study preset');
    }
    await presets(ownerId);
    await customStatement(
      'INSERT INTO study_presets VALUES (?, ?, ?) ON CONFLICT(owner_id, seconds) DO UPDATE SET name = excluded.name',
      [ownerId, seconds, trimmed],
    );
  }

  Future<void> deletePreset(String ownerId, int seconds) async {
    await presets(ownerId);
    await customStatement(
      'DELETE FROM study_presets WHERE owner_id = ? AND seconds = ?',
      [ownerId, seconds],
    );
  }

  Future<Map<String, dynamic>?> accountSnapshot(String ownerId) async {
    final row = await customSelect(
      'SELECT payload FROM account_cache WHERE owner_id = ?',
      variables: [Variable(ownerId)],
    ).getSingleOrNull();
    return row == null
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(row.read<String>('payload')) as Map,
          );
  }

  Future<void> saveAccountSnapshot(String ownerId, Map<String, dynamic> value) {
    if ((value['wallet'] as Map)['owner_id'] != ownerId) {
      throw StateError('Cached wallet identity mismatch');
    }
    return customStatement(
      'INSERT INTO account_cache VALUES (?, ?) ON CONFLICT(owner_id) DO UPDATE SET payload=excluded.payload',
      [ownerId, jsonEncode(value)],
    );
  }

  Future<List<StudySession>> sessions(
    String ownerId,
  ) async => (await customSelect(
    'SELECT * FROM study_sessions WHERE owner_id = ? ORDER BY started_ms, id',
    variables: [Variable(ownerId)],
  ).get()).map(_session).toList();

  static StudySession _session(QueryRow row) => StudySession(
    id: row.read<String>('id'),
    ownerId: row.read<String>('owner_id'),
    runId: row.read<String>('run_id'),
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
    final taskOverlap = await customSelect(
      '''SELECT id FROM task_sessions
      WHERE owner_id = ? AND (state = 'running' OR recorded_ms > ?) LIMIT 1''',
      variables: [
        Variable(session.ownerId),
        Variable(session.startedAt.millisecondsSinceEpoch),
      ],
    ).getSingleOrNull();
    if (taskOverlap != null) {
      throw StateError('A task timer is already running');
    }
    await customStatement(
      '''INSERT INTO study_sessions
      (id, owner_id, started_ms, recorded_ms, state, run_id)
      VALUES (?, ?, ?, ?, ?, ?)''',
      [
        session.id,
        session.ownerId,
        session.startedAt.millisecondsSinceEpoch,
        session.recordedUntil.millisecondsSinceEpoch,
        session.state.name,
        session.runId,
      ],
    );
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

  Future<List<TaskSession>> taskSessions(String ownerId) async =>
      (await customSelect(
            'SELECT * FROM task_sessions WHERE owner_id = ? ORDER BY started_ms, id',
            variables: [Variable(ownerId)],
          ).get())
          .map(
            (row) => TaskSession(
              id: row.read<String>('id'),
              ownerId: row.read<String>('owner_id'),
              activity: TaskActivity.values.byName(
                row.read<String>('activity'),
              ),
              runId: row.readNullable<String>('run_id'),
              runStartedAt: switch (row.readNullable<int>('run_started_ms')) {
                final int value => DateTime.fromMillisecondsSinceEpoch(
                  value,
                  isUtc: true,
                ),
                null => null,
              },
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('started_ms'),
                isUtc: true,
              ),
              recordedUntil: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('recorded_ms'),
                isUtc: true,
              ),
              state: TaskSessionState.values.byName(row.read<String>('state')),
              photoBytes: row.readNullable<Uint8List>('photo_bytes'),
              photoMime: row.readNullable<String>('photo_mime'),
            ),
          )
          .toList();

  Future<void> startTask(TaskSession task) => transaction(() async {
    if (task.state != TaskSessionState.running ||
        task.elapsed != Duration.zero) {
      throw StateError('Task must start at zero');
    }
    final overlap = await customSelect(
      '''SELECT id FROM task_sessions WHERE owner_id = ?
      AND (state = 'running' OR recorded_ms > ?) LIMIT 1''',
      variables: [
        Variable(task.ownerId),
        Variable(task.startedAt.millisecondsSinceEpoch),
      ],
    ).getSingleOrNull();
    final studyOverlap = await customSelect(
      '''SELECT id FROM study_sessions WHERE owner_id = ?
      AND (state = 'running' OR recorded_ms > ?) LIMIT 1''',
      variables: [
        Variable(task.ownerId),
        Variable(task.startedAt.millisecondsSinceEpoch),
      ],
    ).getSingleOrNull();
    if (overlap != null || studyOverlap != null) {
      throw StateError('Another timer is already running');
    }
    await customStatement(
      '''INSERT INTO task_sessions(id,owner_id,activity,started_ms,recorded_ms,state,run_id,run_started_ms)
      VALUES (?,?,?,?,?,?,?,?)''',
      [
        task.id,
        task.ownerId,
        task.activity.name,
        task.startedAt.millisecondsSinceEpoch,
        task.recordedUntil.millisecondsSinceEpoch,
        task.state.name,
        task.runId,
        task.runStartedAt.millisecondsSinceEpoch,
      ],
    );
  });

  Future<void> checkpointTask(TaskSession task) async {
    final count = await customUpdate(
      '''UPDATE task_sessions SET recorded_ms = ?, state = ?
      WHERE id = ? AND owner_id = ? AND started_ms = ? AND state = 'running'
      AND recorded_ms <= ?''',
      variables: [
        Variable(task.recordedUntil.millisecondsSinceEpoch),
        Variable(task.state.name),
        Variable(task.id),
        Variable(task.ownerId),
        Variable(task.startedAt.millisecondsSinceEpoch),
        Variable(task.recordedUntil.millisecondsSinceEpoch),
      ],
      updates: {},
    );
    if (count != 1) throw StateError('Task checkpoint mismatch');
  }

  Future<void> recoverTasks(
    String ownerId,
    StudySession? native,
  ) => transaction(() async {
    if (native != null && native.ownerId == ownerId) {
      final running = (await taskSessions(ownerId))
          .where(
            (task) =>
                task.id == native.id && task.state == TaskSessionState.running,
          )
          .firstOrNull;
      if (running != null &&
          running.startedAt == native.startedAt &&
          native.recordedUntil.isAfter(running.recordedUntil)) {
        await checkpointTask(
          running.checkpoint(native.recordedUntil, stop: true),
        );
      }
    }
    await customStatement(
      "UPDATE task_sessions SET state='pendingPhoto' WHERE owner_id=? AND state='running'",
      [ownerId],
    );
  });

  Future<void> attachTaskPhoto(
    String ownerId,
    String id,
    Uint8List bytes,
  ) async {
    if (bytes.length > 5242880 || bytes.length < 4) {
      throw ArgumentError('Photo must be at most 5 MiB');
    }
    final mime = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff
        ? 'image/jpeg'
        : bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4e &&
              bytes[3] == 0x47
        ? 'image/png'
        : null;
    if (mime == null) {
      throw ArgumentError('Only JPEG or PNG photos are supported');
    }
    final count = await customUpdate(
      '''UPDATE task_sessions SET photo_bytes=?, photo_mime=?
      WHERE id=? AND owner_id=? AND state='pendingPhoto' ''',
      variables: [
        Variable(bytes),
        Variable(mime),
        Variable(id),
        Variable(ownerId),
      ],
      updates: {},
    );
    if (count != 1) throw StateError('Task cannot accept a photo');
  }

  Future<void> queueTask(String ownerId, String id) async {
    final count = await customUpdate(
      '''UPDATE task_sessions SET state='ready' WHERE id=? AND owner_id=?
      AND state='pendingPhoto' ''',
      variables: [Variable(id), Variable(ownerId)],
      updates: {},
    );
    if (count != 1) throw StateError('Task is not awaiting confirmation');
  }

  /// Finish and queue together: a crash cannot leave half a run confirmed.
  Future<void> finishTaskRun(
    String ownerId,
    String runId,
    TaskSession? last,
  ) => transaction(() async {
    if (last != null) await checkpointTask(last);
    await customStatement(
      "UPDATE task_sessions SET state='ready' WHERE owner_id=? AND coalesce(run_id,id)=? AND state='pendingPhoto'",
      [ownerId, runId],
    );
  });

  Future<void> acknowledgeTask(String ownerId, String id) => customStatement(
    "UPDATE task_sessions SET state='synced', photo_bytes=NULL WHERE id=? AND owner_id=? AND state='ready'",
    [id, ownerId],
  );
}
