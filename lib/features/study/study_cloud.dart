import '../../core/storage/app_database.dart';
import '../../core/sync/cloud_client.dart';
import '../identity/identity_repository.dart';
import 'study_session.dart';

class StudySnapshot {
  StudySnapshot(this.wallet, this.days);
  final IdentityWallet wallet;
  final Map<String, Map<String, dynamic>> days;
  factory StudySnapshot.fromJson(Map<String, dynamic> value) => StudySnapshot(
    IdentityWallet.fromJson(Map<String, dynamic>.from(value['wallet'] as Map)),
    {
      for (final raw in value['days'] as List? ?? [])
        (raw as Map)['day'] as String: Map<String, dynamic>.from(raw),
    },
  );
}

class StudyCloud {
  StudyCloud({
    required this.database,
    required this.ownerId,
    required this.onSnapshot,
  });
  final AppDatabase database;
  final String ownerId;
  final void Function(StudySnapshot snapshot) onSnapshot;

  Future<void> submit(StudySession session) => _call('sync_study_run_session', {
    'session_id': session.id,
    'timer_run_id': session.runId,
    'start_at': session.startedAt.toIso8601String(),
    'checkpoint_at': session.recordedUntil.toIso8601String(),
    'is_confirmed':
        session.state == StudySessionState.queued ||
        session.state == StudySessionState.synced,
  });

  Future<void> refresh() => _call('study_state', {});

  Future<void> _call(String method, Map<String, dynamic> params) async {
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Identity changed');
    }
    final raw = await client
        .rpc(method, params: params)
        .timeout(const Duration(seconds: 8));
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Identity changed');
    }
    final value = Map<String, dynamic>.from(raw as Map);
    final snapshot = StudySnapshot.fromJson(value);
    if (snapshot.wallet.ownerId != ownerId) {
      throw StateError('Wallet identity mismatch');
    }
    await database.saveAccountSnapshot(ownerId, value);
    onSnapshot(snapshot);
  }
}
