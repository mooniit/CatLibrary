import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../features/identity/bootstrap_page.dart';
import '../features/identity/identity_repository.dart';

import '../features/home/home_page.dart';
import '../features/study/timer_probe.dart';
import '../features/study/study_page.dart';
import '../features/tasks/task_board_page.dart';
import 'app_theme.dart';

class CatLibraryApp extends StatefulWidget {
  const CatLibraryApp({
    super.key,
    this.preview = false,
    this.initialThemeMode = ThemeMode.light,
  });
  final bool preview;
  final ThemeMode initialThemeMode;

  @override
  State<CatLibraryApp> createState() => _CatLibraryAppState();
}

class _CatLibraryAppState extends State<CatLibraryApp> {
  late ThemeMode themeMode = widget.initialThemeMode;

  Future<void> changeTheme(ThemeMode next) async {
    if (next == themeMode) return;
    final previous = themeMode;
    setState(() => themeMode = next);
    try {
      await saveAppTheme(next);
    } catch (_) {
      if (mounted) setState(() => themeMode = previous);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '喵的图书馆',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    darkTheme: buildAppTheme(Brightness.dark),
    themeMode: themeMode,
    builder: (context, child) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: appSystemBars(dark ? Brightness.dark : Brightness.light),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: widget.preview
        ? PrototypeShell(onThemeChanged: changeTheme)
        : Builder(
            builder: (context) => BootstrapPage(
              initialize: IdentityRepository.bootstrap,
              builder: (wallet) =>
                  PrototypeShell(wallet: wallet, onThemeChanged: changeTheme),
              onPreview: kDebugMode
                  ? () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PrototypeShell(onThemeChanged: changeTheme),
                      ),
                    )
                  : null,
            ),
          ),
  );
}

class PrototypeShell extends StatefulWidget {
  const PrototypeShell({super.key, this.wallet, this.onThemeChanged});
  final IdentityWallet? wallet;
  final Future<void> Function(ThemeMode)? onThemeChanged;
  @override
  State<PrototypeShell> createState() => _PrototypeShellState();
}

class _PrototypeShellState extends State<PrototypeShell>
    with WidgetsBindingObserver {
  int index = 0;
  bool studyFocus = false;
  late IdentityWallet? wallet = widget.wallet;
  Timer? walletRefresh;
  bool refreshingWallet = false;
  final homeKey = GlobalKey<HomePageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (wallet != null) {
      walletRefresh = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(refreshWallet()),
      );
    }
  }

  Future<void> refreshWallet() async {
    if (refreshingWallet || wallet == null) return;
    refreshingWallet = true;
    try {
      final updated = await IdentityRepository.bootstrap();
      if (mounted && updated.ownerId == wallet?.ownerId) {
        setState(() => wallet = updated);
      }
    } catch (_) {
      // Preserve the last confirmed wallet until the next successful read.
    } finally {
      refreshingWallet = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshWallet());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    walletRefresh?.cancel();
    super.dispose();
  }

  Future<void> select(int next) async {
    if (index == 0 && next != 0 && !(await homeKey.currentState!.canLeave())) {
      return;
    }
    if (mounted) setState(() => index = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: index == 3 && wallet != null
        ? null
        : AppBar(
            title: Text(['猫窝', '任务板', '阅读', '自习'][index]),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(30),
              child: Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  wallet == null
                      ? '交互预览 · 无真实资产'
                      : wallet!.cached
                      ? '离线记录中 · 钱包为上次同步余额'
                      : '开发版',
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
            onThemeChanged: widget.onThemeChanged,
            wallet: wallet,
            onWallet: (value) {
              if (mounted) setState(() => wallet = value);
            },
          ),
          if (wallet != null)
            TaskBoardPage(
              ownerId: wallet!.ownerId,
              onWallet: (value) {
                if (mounted) setState(() => wallet = value);
              },
            )
          else
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
                          content: const Text(
                            '这是任务入口原型。当前计时探针仅用于技术验证，不发放任何货币。',
                          ),
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
          if (wallet == null)
            const TimerProbe()
          else
            StudyPage(
              ownerId: wallet!.ownerId,
              onFocusChanged: (value) {
                if (mounted) setState(() => studyFocus = value);
              },
              onWallet: (value) {
                if (mounted) setState(() => wallet = value);
              },
            ),
        ],
      ),
    ),
    bottomNavigationBar: index == 3 && studyFocus
        ? null
        : NavigationBar(
            height: 56,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            selectedIndex: index,
            onDestinationSelected: select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: '猫窝',
              ),
              NavigationDestination(icon: Icon(Icons.checklist), label: '任务板'),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                label: '阅读',
              ),
              NavigationDestination(
                icon: Icon(Icons.timer_outlined),
                label: '自习',
              ),
            ],
          ),
  );
}
