import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../features/identity/bootstrap_page.dart';
import '../features/identity/identity_repository.dart';

import '../features/home/home_page.dart';
import '../features/study/timer_probe.dart';

class CatLibraryApp extends StatelessWidget {
  const CatLibraryApp({super.key, this.preview = false});
  final bool preview;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '喵的图书馆',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xff53665b),
      scaffoldBackgroundColor: const Color(0xfffafaf8),
    ),
    home: preview
        ? const PrototypeShell()
        : Builder(
            builder: (context) => BootstrapPage(
              initialize: IdentityRepository.bootstrap,
              builder: (wallet) => PrototypeShell(wallet: wallet),
              onPreview: kDebugMode
                  ? () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const PrototypeShell(),
                      ),
                    )
                  : null,
            ),
          ),
  );
}

class PrototypeShell extends StatefulWidget {
  const PrototypeShell({super.key, this.wallet});
  final IdentityWallet? wallet;
  @override
  State<PrototypeShell> createState() => _PrototypeShellState();
}

class _PrototypeShellState extends State<PrototypeShell> {
  int index = 0;
  final homeKey = GlobalKey<HomePageState>();
  Future<void> select(int next) async {
    if (index == 0 && next != 0 && !(await homeKey.currentState!.canLeave())) {
      return;
    }
    if (mounted) setState(() => index = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(['猫窝', '任务板', '阅读', '自习'][index]),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(30),
        child: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            widget.wallet == null ? '交互预览 · 无真实资产' : 'M1 开发版 · 计时与领养仍为探针',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    ),
    body: SafeArea(
      child: IndexedStack(
        index: index,
        children: [
          HomePage(
            key: homeKey,
            onStudy: () => select(3),
            wallet: widget.wallet,
          ),
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '今天，做一点喜欢的事',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              for (final title in ['外语学习', '锻炼'])
                Card(
                  child: ListTile(
                    title: Text(title),
                    subtitle: const Text('计时 → 上传照片 → 自行确认\n任务流程待接入'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(title),
                        content: const Text('这是任务入口原型。当前计时探针仅用于技术验证，不发放任何货币。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              const Text('每周特别任务'),
              const Text('内容、数量、刷新时间和奖励仍待确定。'),
            ],
          ),
          const Center(child: Text('阅读功能筹备中')),
          const TimerProbe(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: select,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: '猫窝'),
        NavigationDestination(icon: Icon(Icons.checklist), label: '任务板'),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          label: '阅读',
        ),
        NavigationDestination(icon: Icon(Icons.timer_outlined), label: '自习'),
      ],
    ),
  );
}
