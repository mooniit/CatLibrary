import 'package:flutter/material.dart';
import 'identity_repository.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({
    super.key,
    required this.initialize,
    required this.builder,
    this.onPreview,
  });
  final Future<IdentityWallet> Function() initialize;
  final Widget Function(IdentityWallet) builder;
  final VoidCallback? onPreview;
  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  late Future<IdentityWallet> opening;
  @override
  void initState() {
    super.initState();
    opening = widget.initialize();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<IdentityWallet>(
    future: opening,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        return widget.builder(snapshot.requireData);
      }
      final failed = snapshot.hasError;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '喵的图书馆',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  if (!failed) const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(failed ? '连接失败，请检查网络后重试。' : '正在连接你的小屋…'),
                  const SizedBox(height: 12),
                  const Text(
                    '无需注册。首次使用需要联网，身份会保存在这台设备上。',
                    textAlign: TextAlign.center,
                  ),
                  if (failed)
                    FilledButton(
                      onPressed: () => setState(() {
                        opening = widget.initialize();
                      }),
                      child: const Text('重试连接'),
                    ),
                  if (failed && widget.onPreview != null)
                    TextButton(
                      onPressed: widget.onPreview,
                      child: const Text('进入交互预览（无真实资产）'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
