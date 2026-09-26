import '../storage/app_database.dart';
import '../../features/study/study_session.dart';

typedef SubmitStudy = Future<void> Function(StudySession session);

/// A lost response keeps the immutable record queued under the same session ID.
class StudySyncWorker {
  StudySyncWorker({
    required this.database,
    required this.ownerId,
    required this.submit,
  });
  final AppDatabase database;
  final String ownerId;
  final SubmitStudy submit;
  Future<void>? _active;

  Future<void> sync() =>
      _active ??= _drain().whenComplete(() => _active = null);

  Future<void> _drain() async {
    for (final session in await database.sessions(ownerId)) {
      if (session.state != StudySessionState.queued) continue;
      await submit(session);
      await database.acknowledge(ownerId, session.id);
    }
  }
}
