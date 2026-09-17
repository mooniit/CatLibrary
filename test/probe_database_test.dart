import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/probe_database.dart';

void main() {
  test('SQLite transaction keeps the latest full checkpoint', () async {
    final db = ProbeDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.readCheckpoint(), isNull);
    await db.saveCheckpoint('first');
    await db.saveCheckpoint('second');
    expect(await db.readCheckpoint(), 'second');
  });
  test('file-backed SQLite checkpoint survives a closed connection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'catlibrary_probe_',
    );
    final file = File('${directory.path}/probe.sqlite');
    final first = ProbeDatabase(NativeDatabase(file));
    await first.saveCheckpoint('durable record');
    await first.close();
    final reopened = ProbeDatabase(NativeDatabase(file));
    try {
      expect(await reopened.readCheckpoint(), 'durable record');
    } finally {
      await reopened.close();
      await file.delete();
      await directory.delete();
    }
  });
}
