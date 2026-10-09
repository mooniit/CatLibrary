import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/app_database.dart';
import 'cloud_connection.dart';
import 'identity_guard.dart';
import 'legacy_session_recovery.dart';

class CloudClient {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  static Future<SupabaseClient>? _opening;
  static bool _initialized = false;
  static final connection = CloudConnection();
  static bool get configured => url.isNotEmpty && key.isNotEmpty;
  static Future<SupabaseClient> connect() =>
      _opening ??= _connect().catchError((Object e) {
        _opening = null;
        throw e;
      });
  static Future<SupabaseClient> _connect() async {
    if (!configured) {
      connection.unconfigured();
      throw StateError('尚未配置服务');
    }
    if (!_initialized) {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        debug: false,
        httpClient: ConnectionHttpClient(http.Client(), connection),
      );
      _initialized = true;
    }
    final client = Supabase.instance.client;
    final preferences = await SharedPreferences.getInstance();
    final cachedOwners =
        (await AppDatabase.shared
                .customSelect('SELECT owner_id FROM account_cache')
                .get())
            .map((row) => row.read<String>('owner_id'))
            .toList();
    if (client.auth.currentSession == null) {
      final transport = ConnectionHttpClient(http.Client(), connection);
      try {
        await LegacySessionRecovery.recover(
          targetUrl: url,
          publicKey: key,
          preferences: preferences,
          transport: transport,
          rememberedOwner: preferences.getString('identity_original_owner'),
          cachedOwners: cachedOwners,
          restoreSession: (value) async {
            await client.auth.recoverSession(value);
          },
        );
      } finally {
        transport.close();
      }
    }
    IdentityGuard.check(
      client.auth.currentUser?.id,
      rememberedOwner: preferences.getString('identity_original_owner'),
      cachedOwners: cachedOwners,
    );
    if (client.auth.currentSession == null) {
      await client.auth.signInAnonymously();
    }
    await preferences.setString(
      'identity_original_owner',
      client.auth.currentUser!.id,
    );
    return client;
  }

  static Future<String> runProbe() async {
    final client = await connect();
    final id = client.auth.currentUser!.id;
    final marker = DateTime.now().toUtc().toIso8601String();
    await client.from('m0_probe_notes').upsert({
      'owner_id': id,
      'note': marker,
    });
    final row = await client
        .from('m0_probe_notes')
        .select()
        .eq('owner_id', id)
        .single();
    if (row['note'] != marker) throw StateError('样例回读不一致');
    // A synthetic PNG tests transport only, never a real user task photo.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final bucket = client.storage.from('m0-probe-private');
    final path = '$id/probe.png';
    await bucket.uploadBinary(
      path,
      png,
      fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
    );
    final back = await bucket.download(path);
    if (base64Encode(back) != base64Encode(png)) throw StateError('文件回读不一致');
    return '当前设备：匿名身份、样例写入/读取、私有样例图片往返成功。\n用户编号：$id\n不代表双设备隔离、家庭共享或真实云端验收通过。';
  }
}

class CloudProbePanel extends StatefulWidget {
  const CloudProbePanel({super.key});
  @override
  State<CloudProbePanel> createState() => _CloudProbePanelState();
}

class _CloudProbePanelState extends State<CloudProbePanel> {
  bool busy = false;
  String result = CloudClient.configured ? '测试项目已配置，等待验证' : '未配置 Supabase 测试项目';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '设置 · M0 验证',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text('正式设置项、邀请方式和通知渠道仍待 Q12 确认。'),
            const SizedBox(height: 16),
            Text(result),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy || !CloudClient.configured
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final text = await CloudClient.runProbe();
                        if (mounted) setState(() => result = text);
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () =>
                                result = '验证失败：检查网络、匿名身份开关、迁移和存储权限。未确认成功，可重试。',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(busy ? '验证中…' : '验证连接与私有样例文件'),
            ),
            const SizedBox(height: 16),
            const Text(
              '此按钮仅操作 m0_probe_notes 与 m0-probe-private 样例，不创建钱包、家庭或业务账目。',
            ),
          ],
        ),
      ),
    ),
  );
}
