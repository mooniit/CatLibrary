/// Durable evidence, kept in milliseconds so reward rounding can happen per day.
class StudySession {
  StudySession({
    required this.id,
    required this.ownerId,
    required DateTime startedAt,
    required DateTime recordedUntil,
    required this.state,
    String? runId,
  }) : startedAt = startedAt.toUtc(),
       recordedUntil = recordedUntil.toUtc(),
       runId = runId ?? id {
    if (id.isEmpty ||
        ownerId.isEmpty ||
        this.runId.isEmpty ||
        this.recordedUntil.isBefore(this.startedAt) ||
        this.recordedUntil.difference(this.startedAt) > maximumDuration) {
      throw ArgumentError('Invalid study evidence');
    }
  }

  static const maximumDuration = Duration(hours: 6);
  final String id;
  final String ownerId;

  /// Several active intervals may belong to one timer after pause/resume.
  final String runId;
  final DateTime startedAt;
  final DateTime recordedUntil;
  final StudySessionState state;
  Duration get elapsed => recordedUntil.difference(startedAt);

  StudySession checkpoint(DateTime now, {bool stop = false}) {
    if (state != StudySessionState.running) return this;
    final limit = startedAt.add(maximumDuration);
    final utc = now.toUtc();
    final end = utc.isBefore(recordedUntil)
        ? recordedUntil
        : utc.isAfter(limit)
        ? limit
        : utc;
    return StudySession(
      id: id,
      ownerId: ownerId,
      runId: runId,
      startedAt: startedAt,
      recordedUntil: end,
      state: stop || !end.isBefore(limit)
          ? StudySessionState.pendingConfirmation
          : StudySessionState.running,
    );
  }

  StudySession recover() => StudySession(
    id: id,
    ownerId: ownerId,
    runId: runId,
    startedAt: startedAt,
    recordedUntil: recordedUntil,
    state: state == StudySessionState.running
        ? StudySessionState.pendingConfirmation
        : state,
  );
}

enum StudySessionState { running, pendingConfirmation, queued, synced }
