import 'dart:typed_data';

enum TaskActivity { language, exercise }

extension TaskActivityLabel on TaskActivity {
  String get label => this == TaskActivity.language ? '外语学习' : '锻炼';
  String get rewardLabel => this == TaskActivity.language ? '鹰镑' : '宝石';
}

enum TaskSessionState { running, pendingPhoto, ready, synced }

class TaskSession {
  TaskSession({
    required this.id,
    required this.ownerId,
    required this.activity,
    required DateTime startedAt,
    required DateTime recordedUntil,
    required this.state,
    this.photoBytes,
    this.photoMime,
  }) : startedAt = startedAt.toUtc(),
       recordedUntil = recordedUntil.toUtc() {
    if (id.isEmpty ||
        ownerId.isEmpty ||
        this.recordedUntil.isBefore(this.startedAt) ||
        this.recordedUntil.difference(this.startedAt) >
            const Duration(hours: 6)) {
      throw ArgumentError('Invalid task interval');
    }
  }

  final String id, ownerId;
  final TaskActivity activity;
  final DateTime startedAt, recordedUntil;
  final TaskSessionState state;
  final Uint8List? photoBytes;
  final String? photoMime;

  Duration get elapsed => recordedUntil.difference(startedAt);
  String get photoPath => '$ownerId/$id';

  TaskSession checkpoint(DateTime instant, {bool stop = false}) {
    final utc = instant.toUtc();
    final end = utc.isAfter(startedAt.add(const Duration(hours: 6)))
        ? startedAt.add(const Duration(hours: 6))
        : utc.isBefore(recordedUntil)
        ? recordedUntil
        : utc;
    return TaskSession(
      id: id,
      ownerId: ownerId,
      activity: activity,
      startedAt: startedAt,
      recordedUntil: end,
      state: stop || end.difference(startedAt) == const Duration(hours: 6)
          ? TaskSessionState.pendingPhoto
          : TaskSessionState.running,
      photoBytes: photoBytes,
      photoMime: photoMime,
    );
  }
}
