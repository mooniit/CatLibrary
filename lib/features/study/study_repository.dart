import 'dart:math';

import '../../core/storage/app_database.dart';
import 'study_session.dart';

/// Serializes lifecycle/button writes so an old tick cannot overwrite a stop.
class StudyRepository {
  StudyRepository({
    required this.database,
    required this.ownerId,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final AppDatabase database;
  final String ownerId;
  final DateTime Function() now;
  StudySession? active;
  bool needsRecovery = true;
  Future<void> _writes = Future.value();

  Future<void> _serial(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> recover({StudySession? durableNative}) => _serial(() async {
    active = null;
    needsRecovery = true;
    if (durableNative != null && durableNative.ownerId == ownerId) {
      final saved = (await records())
          .where((s) => s.id == durableNative.id)
          .firstOrNull;
      if (saved != null &&
          saved.state == StudySessionState.running &&
          saved.startedAt.millisecondsSinceEpoch ==
              durableNative.startedAt.millisecondsSinceEpoch &&
          durableNative.recordedUntil.isAfter(saved.recordedUntil)) {
        await database.checkpoint(
          saved.checkpoint(durableNative.recordedUntil, stop: true),
        );
      }
    }
    await database.recover(ownerId);
    needsRecovery = false;
  });

  Future<List<StudySession>> records() => database.sessions(ownerId);

  Future<void> start({String? runId}) => _serial(() async {
    if (needsRecovery || active != null) {
      throw StateError('Study is not ready to start');
    }
    final instant = now().toUtc();
    final record = StudySession(
      id: _newId(),
      ownerId: ownerId,
      runId: runId,
      startedAt: instant,
      recordedUntil: instant,
      state: StudySessionState.running,
    );
    // Never show a running timer before its initial record is durable.
    await database.start(record);
    active = record;
  });

  Future<void> checkpoint({bool stop = false, DateTime? at}) => _serial(
    () async {
      if (needsRecovery) throw StateError('Recover storage before continuing');
      final previous = active;
      if (previous == null) return;
      final next = previous.checkpoint(at ?? now(), stop: stop);
      try {
        await database.checkpoint(next);
        active = next.state == StudySessionState.running ? next : null;
      } catch (_) {
        // A failed write cannot be represented as successful elapsed time.
        active = null;
        needsRecovery = true;
        rethrow;
      }
    },
  );

  Future<void> confirm(String id) => _serial(() async {
    if (needsRecovery) throw StateError('Recover storage before confirming');
    await database.confirm(ownerId, id, now());
  });

  static String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
