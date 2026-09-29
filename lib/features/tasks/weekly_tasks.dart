import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/app_database.dart';
import '../../core/sync/cloud_client.dart';
import '../identity/identity_repository.dart';

class WeeklyTask {
  WeeklyTask.fromJson(Map<String, dynamic> json)
    : offerId = json['offer_id'] as String,
      taskId = json['task_id'] as String,
      prompt = json['prompt'] as String,
      evidenceKind = json['evidence_kind'] as String,
      imageCount = json['image_count'] as int,
      weekStart = json['week_start'] as String,
      confirmedAt = json['confirmed_at'] == null
          ? null
          : DateTime.parse(json['confirmed_at'] as String);

  final String offerId, taskId, prompt, evidenceKind, weekStart;
  final int imageCount;
  final DateTime? confirmedAt;
  String get evidenceLabel => switch (evidenceKind) {
    'text' => '填写简短文字（最多 100 字）',
    'screenshot' => '上传 1 张记录三句的截图',
    'photo' => '上传 $imageCount 张照片',
    _ => '自行确认',
  };

  bool isCurrent(DateTime at) {
    final beijing = at.toUtc().add(const Duration(hours: 8));
    final monday = DateTime.utc(
      beijing.year,
      beijing.month,
      beijing.day,
    ).subtract(Duration(days: beijing.weekday - 1));
    return monday.toIso8601String().substring(0, 10) == weekStart;
  }
}

class WeeklyRepository {
  WeeklyRepository(this.database, this.ownerId);
  final AppDatabase database;
  final String ownerId;

  Future<List<WeeklyTask>> cachedTasks() async => [
    for (final item in await database.weeklyOffers(ownerId))
      WeeklyTask.fromJson(item),
  ];
  Future<List<WeeklyDraft>> drafts() => database.weeklyDrafts(ownerId);
  Future<void> saveNote(WeeklyTask task, String value) =>
      database.saveWeeklyNote(ownerId, task.offerId, value);
  Future<void> savePhoto(WeeklyTask task, int slot, Uint8List bytes) async {
    if (slot >= task.imageCount) throw ArgumentError('Unexpected photo slot');
    await database.saveWeeklyPhoto(ownerId, task.offerId, slot, bytes);
  }

  Future<void> confirm(WeeklyTask task, DateTime at) async {
    if (!task.isCurrent(at)) throw StateError('Weekly task has refreshed');
    final draft = (await drafts())
        .where((d) => d.offerId == task.offerId)
        .firstOrNull;
    if (task.evidenceKind == 'text' && (draft?.note.trim().isEmpty ?? true)) {
      throw StateError('Text evidence required');
    }
    for (var i = 0; i < task.imageCount; i++) {
      if (draft?.photos[i] == null) throw StateError('Required photo missing');
    }
    await database.queueWeekly(ownerId, task.offerId, at);
  }
}

class WeeklyCloud {
  WeeklyCloud(this.database, this.ownerId, this.onWallet);
  final AppDatabase database;
  final String ownerId;
  final ValueChanged<IdentityWallet> onWallet;

  Future<SupabaseClient> _client() async {
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Identity changed');
    }
    return client;
  }

  Future<List<WeeklyTask>> refresh() async {
    final client = await _client();
    final raw = await client
        .rpc('weekly_my_tasks')
        .timeout(const Duration(seconds: 10));
    final items = [
      for (final item in raw as List) Map<String, dynamic>.from(item as Map),
    ];
    // Keep older offers while a Sunday confirmation is waiting to sync.
    final cached = {
      for (final item in await database.weeklyOffers(ownerId))
        item['offer_id'] as String: item,
    };
    for (final item in items) {
      cached[item['offer_id'] as String] = item;
    }
    await database.saveWeeklyOffers(ownerId, cached.values.toList());
    return [for (final item in items) WeeklyTask.fromJson(item)];
  }

  Future<List<Map<String, dynamic>>> familyFeed() async {
    final client = await _client();
    final raw = await client
        .rpc('weekly_family_feed')
        .timeout(const Duration(seconds: 10));
    return [
      for (final item in raw as List) Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<void> submit(WeeklyTask task, WeeklyDraft draft) async {
    if (draft.state != 'ready' || draft.confirmedAt == null) return;
    final client = await _client();
    final already = (await familyFeed()).any(
      (item) => item['offer_id'] == task.offerId && item['owner_id'] == ownerId,
    );
    if (already) {
      await _refreshWallet(client);
      await database.acknowledgeWeekly(ownerId, task.offerId);
      return;
    }
    await client
        .rpc(
          'weekly_save_draft',
          params: {
            'target_offer': task.offerId,
            'draft_note': task.evidenceKind == 'text' ? draft.note : null,
          },
        )
        .timeout(const Duration(seconds: 10));
    final bucket = client.storage.from('weekly-photos');
    for (var slot = 0; slot < task.imageCount; slot++) {
      final bytes = draft.photos[slot], mime = draft.mimes[slot];
      if (bytes == null || mime == null) {
        throw StateError('Local photo missing');
      }
      await bucket.uploadBinary(
        '$ownerId/${task.offerId}/$slot',
        bytes,
        fileOptions: FileOptions(contentType: mime, upsert: true),
      );
    }
    final raw = Map<String, dynamic>.from(
      await client
              .rpc(
                'weekly_confirm',
                params: {
                  'target_offer': task.offerId,
                  'claimed_at': draft.confirmedAt!.toUtc().toIso8601String(),
                },
              )
              .timeout(const Duration(seconds: 10))
          as Map,
    );
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Identity changed');
    }
    await _acceptWallet(Map<String, dynamic>.from(raw['wallet'] as Map));
    await database.acknowledgeWeekly(ownerId, task.offerId);
  }

  Future<void> _refreshWallet(SupabaseClient client) async {
    final raw = Map<String, dynamic>.from(
      await client.rpc('task_state') as Map,
    );
    await _acceptWallet(Map<String, dynamic>.from(raw['wallet'] as Map));
  }

  Future<void> _acceptWallet(Map<String, dynamic> raw) async {
    final wallet = IdentityWallet.fromJson(raw);
    if (wallet.ownerId != ownerId) throw StateError('Wallet identity mismatch');
    final cached = await database.accountSnapshot(ownerId);
    await database.saveAccountSnapshot(ownerId, {
      'wallet': raw,
      'days': cached?['days'] ?? [],
    });
    onWallet(wallet);
  }

  Future<Uint8List> photo(String path) async =>
      (await _client()).storage.from('weekly-photos').download(path);
}
