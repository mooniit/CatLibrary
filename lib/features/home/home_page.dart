import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../room/room_scene.dart';
import '../cats/cats_page.dart';
import '../cats/cats_repository.dart';
import '../identity/identity_repository.dart';
import '../wallet/exchange_sheet.dart';
import '../wallet/proxy_payment_notice.dart';
import '../repair/repair_panel.dart';
import '../settings/settings_page.dart';
import 'home_controls.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onStudy,
    this.wallet,
    this.onWallet,
    this.onThemeChanged,
    this.loadCats,
  });
  final IdentityWallet? wallet;
  final VoidCallback onStudy;
  final ValueChanged<IdentityWallet>? onWallet;
  final Future<void> Function(ThemeMode)? onThemeChanged;
  final Future<Map<String, dynamic>> Function()? loadCats;
  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final scene = RoomScene();
  String? catsError;
  bool loadingCats = false;
  bool hasFamily = false;
  int _request = 0;
  double _startZoom = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refreshCats());
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallet?.ownerId != widget.wallet?.ownerId) {
      scene.cats = [];
      hasFamily = false;
      unawaited(refreshCats());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshCats());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refreshCats() async {
    final request = ++_request;
    if (widget.wallet == null) {
      scene.cats = [
        (name: '三花猫', appearance: 'black_short'),
        (name: '蓝眸长毛猫', appearance: 'light_long'),
      ];
      setState(() {
        loadingCats = false;
        catsError = null;
      });
      return;
    }
    setState(() {
      loadingCats = true;
      catsError = null;
    });
    try {
      final result =
          await (widget.loadCats?.call() ??
                  CatsRepository.call('cats_state', const {}))
              .timeout(const Duration(seconds: 8));
      if (!mounted || request != _request) return;
      final cats = [
        for (final cat in result['cats'] as List)
          (
            name: cat['name'] as String,
            appearance: cat['appearance'] as String,
          ),
      ];
      setState(() {
        scene.cats = cats;
        hasFamily = result['family_id'] != null;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => catsError = '猫咪暂未同步，点击重试');
      }
    } finally {
      if (mounted && request == _request) setState(() => loadingCats = false);
    }
  }

  void info(String title, String text) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(text),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );

  void openStore() {
    final wallet = widget.wallet;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text('商店', style: Theme.of(c).textTheme.headlineSmall),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text('家具款式尚未上架。'),
              ),
              if (wallet != null)
                ExchangeSheet(
                  wallet: wallet,
                  onWallet: (value) => widget.onWallet?.call(value),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('连接钱包后可兑换币种。'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openCats() async {
    final wallet = widget.wallet;
    if (wallet == null) {
      info('猫咪管理', '请先连接服务并加入小屋。交互预览不会创建猫咪。');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CatsPage(ownerId: wallet.ownerId, onWallet: widget.onWallet),
      ),
    );
    if (mounted) await refreshCats();
  }

  Future<void> openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          onThemeChanged: widget.onThemeChanged,
          ownerId: widget.wallet?.ownerId,
        ),
      ),
    );
    if (mounted) await refreshCats();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = widget.wallet;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          const SkyBackground(),
          GestureDetector(
            key: const Key('room-viewport'),
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => setState(scene.resetView),
            onScaleStart: (_) {
              _startZoom = scene.zoom;
            },
            onScaleUpdate: (event) => setState(() {
              scene.moveView(
                _startZoom * event.scale,
                event.localFocalPoint,
                event.focalPointDelta,
              );
            }),
            child: Semantics(
              label:
                  '猫窝，拖动查看，双指缩放，双击回到初始视角。${scene.cats.map((c) => c.name).join('、')}',
              child: GameWidget(
                game: scene,
                loadingBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, _) =>
                    const Center(child: Text('猫窝素材加载失败，请重新打开页面')),
              ),
            ),
          ),
          if (wallet != null)
            ProxyPaymentNotice(
              key: ValueKey('notice-${wallet.ownerId}'),
              ownerId: wallet.ownerId,
            ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: HomeWallet(wallet: wallet),
          ),
          Positioned(
            top: 80,
            right: 12,
            child: HomeMenu(
              onCats: openCats,
              onStore: openStore,
              onAlbum: () => info('相册', '还没有旅行照片。'),
              onSettings: openSettings,
            ),
          ),
          if (scene.pan.distance > 1 || scene.zoom != 1)
            Positioned(
              bottom: 16,
              right: 16,
              child: RoomActionButton(
                label: '回到初始视角',
                icon: Icons.center_focus_strong_outlined,
                onPressed: () => setState(scene.resetView),
              ),
            ),
          Positioned(
            top: 80,
            left: 16,
            right: 156,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.35,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (wallet == null)
                      status('交互预览 · 示例猫咪', null)
                    else if (wallet.cached)
                      status('离线 · 钱包为上次同步余额', null),
                    if ((wallet?.miaoCoins ?? 0) < 0)
                      status('喵喵币欠款 ${-wallet!.miaoCoins}', null),
                    if (loadingCats)
                      status('正在同步猫咪…', null)
                    else if (catsError != null)
                      status(catsError!, refreshCats)
                    else if (wallet != null && scene.cats.isEmpty)
                      status(hasFamily ? '认识第一只猫咪' : '创建或加入小屋', openCats),
                    if (wallet != null)
                      RepairPanel(
                        key: ValueKey('repair-${wallet.ownerId}'),
                        ownerId: wallet.ownerId,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget status(String text, VoidCallback? onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(text, style: const TextStyle(fontSize: 12)),
        ),
      ),
    ),
  );
}
