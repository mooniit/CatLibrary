import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../room_layout.dart';
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
  final layout = RoomLayout();
  late final scene = RoomScene(layout);
  String? catsError;
  bool loadingCats = false;
  bool hasFamily = false;
  int _request = 0;
  double _startZoom = 1;
  Offset _drag = Offset.zero;
  GridPoint? _startFurniture;

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

  Future<bool> canLeave() async {
    if (!layout.editing) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('离开布置？'),
        content: const Text('未保存的布置草稿将被放弃。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('继续布置'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (discard == true) setState(layout.cancel);
    return discard == true;
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

  void openWallet() {
    final wallet = widget.wallet;
    if (wallet == null) {
      info('个人钱包', '交互预览未连接钱包，画面中的猫咪为示例。');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExchangeSheet(
        wallet: wallet,
        onWallet: (value) => widget.onWallet?.call(value),
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
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !layout.editing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) canLeave();
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerLow),
            GestureDetector(
              key: const Key('room-viewport'),
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => setState(scene.resetView),
              onScaleStart: (_) {
                _startZoom = scene.zoom;
                _drag = Offset.zero;
                _startFurniture = layout.editing
                    ? layout.draft[scene.selected]
                    : null;
              },
              onScaleUpdate: (event) => setState(() {
                if (layout.editing &&
                    event.pointerCount == 1 &&
                    _startFurniture != null) {
                  _drag += event.focalPointDelta;
                  final delta = scene.gridDelta(_drag);
                  layout.move(
                    scene.selected,
                    GridPoint(
                      _startFurniture!.x + delta.x,
                      _startFurniture!.y + delta.y,
                    ),
                  );
                } else {
                  scene.moveView(
                    _startZoom * event.scale,
                    event.localFocalPoint,
                    event.focalPointDelta,
                  );
                  _startFurniture = null;
                }
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
              child: HomeWallet(wallet: wallet, onTap: openWallet),
            ),
            Positioned(
              top: 72,
              right: 12,
              child: RoomActionButton(
                label: '设置',
                icon: Icons.settings_outlined,
                onPressed: openSettings,
              ),
            ),
            if (scene.pan.distance > 1 || scene.zoom != 1)
              Positioned(
                top: 128,
                right: 12,
                child: RoomActionButton(
                  label: '回到初始视角',
                  icon: Icons.center_focus_strong_outlined,
                  onPressed: () => setState(scene.resetView),
                ),
              ),
            Positioned(
              top: 68,
              left: 16,
              right: 72,
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
                        status('喵喵币欠款 ${-wallet!.miaoCoins}', openWallet),
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
            Positioned(
              left: 16,
              right: 16,
              bottom: 60,
              child: layout.editing
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.55,
                      ),
                      child: SingleChildScrollView(
                        child: FurnitureControls(
                          layout: layout,
                          selected: scene.selected,
                          onSelect: (id) => setState(() => scene.selected = id),
                          onMove: (delta) => setState(() {
                            final p = layout.draft[scene.selected]!;
                            layout.move(
                              scene.selected,
                              GridPoint(p.x + delta.dx, p.y + delta.dy),
                            );
                          }),
                          onSave: () {
                            setState(layout.commit);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已保留本次预览布局（仅当前运行，无云端保存）'),
                              ),
                            );
                          },
                          onCancel: () => setState(layout.cancel),
                        ),
                      ),
                    )
                  : Row(
                      key: const Key('room-actions'),
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        RoomActionButton(
                          label: '布置猫窝',
                          icon: Icons.chair_outlined,
                          onPressed: () => setState(layout.beginEditing),
                        ),
                        RoomActionButton(
                          label: '猫咪管理',
                          icon: Icons.pets_outlined,
                          onPressed: openCats,
                        ),
                        RoomActionButton(
                          label: '商店',
                          icon: Icons.storefront_outlined,
                          onPressed: () =>
                              info('商店', '这里将展示可购买家具。商品、币种、价格尚未确定，当前不能购买。'),
                        ),
                        RoomActionButton(
                          label: '相册',
                          icon: Icons.photo_library_outlined,
                          onPressed: () =>
                              info('相册', '还没有旅行照片。此处是空状态原型，不生成旅行记录。'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
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
