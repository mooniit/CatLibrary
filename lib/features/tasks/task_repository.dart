import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/app_database.dart';
import '../../core/sync/cloud_client.dart';
import '../identity/identity_repository.dart';
import '../study/study_session.dart';
import 'task_session.dart';

class TaskRepository {
  TaskRepository({
    required this.database,
    required this.ownerId,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final AppDatabase database;
  final String ownerId;
  final DateTime Function() now;
  TaskSession? active;
  bool needsRecovery = true;
  Future<void> _writes = Future.value();

  Future<void> _serial(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<TaskSession>> records() => database.taskSessions(ownerId);

  Future<void> recover(StudySession? native) => _serial(() async {
    needsRecovery = true;
    active = null;
    await database.recoverTasks(ownerId, native);
    needsRecovery = false;
  });

  Future<void> start(TaskActivity activity) => _serial(() async {
    if (needsRecovery || active != null) {
      throw StateError('Task timer is not ready');
    }
    final instant = now().toUtc();
    final record = TaskSession(
      id: _newId(),
      ownerId: ownerId,
      activity: activity,
      startedAt: instant,
      recordedUntil: instant,
      state: TaskSessionState.running,
    );
    await database.startTask(record);
    active = record;
  });

  Future<void> checkpoint({bool stop = false, DateTime? at}) => _serial(
    () async {
      if (needsRecovery) throw StateError('Recover task timer before writing');
      final previous = active;
      if (previous == null) return;
      final next = previous.checkpoint(at ?? now(), stop: stop);
      try {
        await database.checkpointTask(next);
        active = next.state == TaskSessionState.running ? next : null;
      } catch (_) {
        active = null;
        needsRecovery = true;
        rethrow;
      }
    },
  );

  Future<void> attachPhoto(String id, Uint8List bytes) =>
      _serial(() => database.attachTaskPhoto(ownerId, id, bytes));

  Future<void> confirm(String id) =>
      _serial(() => database.queueTask(ownerId, id));

  static String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class TaskCloud {
  TaskCloud({
    required this.database,
    required this.ownerId,
    required this.onWallet,
  });
  final AppDatabase database;
  final String ownerId;
  final ValueChanged<IdentityWallet> onWallet;
  List<Map<String, dynamic>> days = [];

  Future<SupabaseClient> _client() async {
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Identity changed');
    }
    return client;
  }

  Future<void> sync(TaskSession session) async {
    if (session.ownerId != ownerId || session.state == TaskSessionState.synced) {
      return;
    }
    final client = await _client();
    final params = {
      'session_id': session.id,
      'task_activity': session.activity.name,
      'start_at': session.startedAt.toIso8601String(),
      'checkpoint_at': session.recordedUntil.toIso8601String(),
      'task_photo_path': null,
      'is_confirmed': false,
    };
    var raw = await client
        .rpc('sync_task_session', params: params)
        .timeout(const Duration(seconds: 10));
    if (session.state == TaskSessionState.ready) {
      final bytes = session.photoBytes;
      if (bytes == null || session.photoMime == null) {
        throw StateError('Photo evidence missing from local queue');
      }
      final bucket = client.storage.from('task-photos');
      try {
        await bucket.uploadBinary(
          session.photoPath,
          bytes,
          fileOptions: FileOptions(
            contentType: session.photoMime,
            upsert: false,
          ),
        );
      } on StorageException catch (error) {
        if (error.statusCode != '409') rethrow;
        final existing = await bucket.download(session.photoPath);
        if (!listEquals(existing, bytes)) {
          throw StateError(
            'A different photo was already uploaded for this task',
          );
        }
      }
      raw = await client
          .rpc(
            'sync_task_session',
            params: {
              ...params,
              'task_photo_path': session.photoPath,
              'is_confirmed': true,
            },
          )
          .timeout(const Duration(seconds: 10));
      await database.acknowledgeTask(ownerId, session.id);
    }
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Identity changed');
    }
    await _accept(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> refresh() async {
    final client = await _client();
    final raw = await client
        .rpc('task_state')
        .timeout(const Duration(seconds: 10));
    await _accept(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> _accept(Map<String, dynamic> raw) async {
    final wallet = IdentityWallet.fromJson(
      Map<String, dynamic>.from(raw['wallet'] as Map),
    );
    if (wallet.ownerId != ownerId) throw StateError('Wallet identity mismatch');
    days = [
      for (final item in raw['days'] as List)
        Map<String, dynamic>.from(item as Map),
    ];
    final cached = await database.accountSnapshot(ownerId);
    await database.saveAccountSnapshot(ownerId, {
      'wallet': raw['wallet'],
      'days': cached?['days'] ?? [],
    });
    onWallet(wallet);
  }

  Future<List<Map<String, dynamic>>> feed() async {
    final client = await _client();
    final raw = await client
        .rpc('task_feed')
        .timeout(const Duration(seconds: 10));
    return [
      for (final item in raw as List) Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<Uint8List> photo(String path) async {
    final client = await _client();
    return client.storage.from('task-photos').download(path);
  }
}
