import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/sync/cloud_client.dart';

class ProxyPaymentNotice extends StatefulWidget {
  const ProxyPaymentNotice({
    super.key,
    required this.ownerId,
    this.load,
    this.acknowledge,
  });

  final String ownerId;
  final Future<List<Map<String, dynamic>>> Function()? load;
  final Future<void> Function(String day)? acknowledge;

  @override
  State<ProxyPaymentNotice> createState() => _ProxyPaymentNoticeState();
}

class _ProxyPaymentNoticeState extends State<ProxyPaymentNotice>
    with WidgetsBindingObserver {
  Timer? timer;
  bool checking = false;

  Future<SupabaseClient> _client() async {
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != widget.ownerId) {
      throw StateError('Identity changed');
    }
    return client;
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await (await _client())
        .rpc('proxy_notice_state')
        .timeout(const Duration(seconds: 8));
    return [
      for (final item in raw as List) Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<void> _ack(String day) async {
    await (await _client())
        .rpc('ack_proxy_notice', params: {'target_day': day})
        .timeout(const Duration(seconds: 8));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
    timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_check()),
    );
  }

  Future<void> _check() async {
    if (checking || !mounted) return;
    checking = true;
    try {
      final notices = await (widget.load ?? _load)();
      if (!mounted || notices.isEmpty) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('家庭代扣提醒'),
          content: Text(
            notices
                .map((item) => '${item['day']}：为家庭猫咪代付 ${item['paid']} 喵喵币')
                .join('\n'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      for (final item in notices) {
        await (widget.acknowledge ?? _ack)(item['day'] as String);
      }
    } catch (_) {
      // A failed read or acknowledgment remains pending on the server.
    } finally {
      checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
