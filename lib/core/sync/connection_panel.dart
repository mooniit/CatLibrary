import 'package:flutter/material.dart';
import '../../features/identity/identity_repository.dart';
import 'cloud_client.dart';
import 'cloud_connection.dart';

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({super.key});
  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  bool busy = false;
  String? message;
  Future<void> retry() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final wallet = await IdentityRepository.bootstrap();
      if (mounted) {
        setState(
          () => message = wallet.cached
              ? '暂未连接，保留上次确认的余额与本地记录。'
              : '已重新连接，账户与余额已核对。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => message = '连接未恢复。原有账户与记录已保留，请稍后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = CloudConnection.isLocalEndpoint(CloudClient.url);
    return ValueListenableBuilder<CloudStatus>(
      valueListenable: CloudClient.connection,
      builder: (context, status, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.phase == CloudPhase.online
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    container: true,
                    label: CloudClient.configured ? status.label : '尚未配置在线服务',
                    excludeSemantics: true,
                    child: Text(
                      CloudClient.configured ? status.label : '尚未配置在线服务',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '重新连接',
                  onPressed: busy || !CloudClient.configured ? null : retry,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              local
                  ? '当前连接电脑上的本地测试服务，手机联网本身无法访问它。正式在线使用需要云端地址；本地调试需保持电脑服务和 USB 连接。'
                  : '余额、家庭库存与正式布局由在线服务核对。连接中断时保留本地记录与草稿，重连后先核对原请求结果。',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            if (CloudClient.configured) ...[
              const SizedBox(height: 12),
              SelectableText(
                Uri.tryParse(CloudClient.url)?.origin ?? '服务地址无效',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  container: true,
                  label: message!,
                  excludeSemantics: true,
                  child: Text(message!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
