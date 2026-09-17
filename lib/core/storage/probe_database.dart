import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Small probe schema. Production records and synchronization belong to M2.
class ProbeDatabase extends GeneratedDatabase {
  ProbeDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'cat_library_m0'));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE probe_records (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)',
      );
    },
  );
  Future<String?> readCheckpoint() async {
    final row = await customSelect(
      'SELECT payload FROM probe_records WHERE id = 1',
    ).getSingleOrNull();
    return row?.read<String>('payload');
  }

  Future<void> saveCheckpoint(String payload) => transaction(() async {
    await customStatement(
      'INSERT INTO probe_records(id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload',
      [payload],
    );
  });
}
