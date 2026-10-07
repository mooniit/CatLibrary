import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/storage/app_database.dart';
import '../identity/identity_repository.dart';
import '../room/layout_draft.dart';
import '../room/room_scene.dart';
import '../room/furniture_catalog_widgets.dart';
import 'shop_repository.dart';
import 'shop_preview.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({
    super.key,
    required this.wallet,
    this.onWallet,
    this.repository,
    required this.scene,
  });
  final IdentityWallet wallet;
  final ValueChanged<IdentityWallet>? onWallet;
  final ShopRepository? repository;
  final RoomScene scene;
  @override
  State<ShopPage> createState() => ShopPageState();
}

class ShopPageState extends State<ShopPage> {
  late final repo =
      widget.repository ??
      ShopRepository(AppDatabase.shared, widget.wallet.ownerId);
  late final scene = widget.scene;
  FurnitureState? state;
  ShopPreview? preview;
  Map<String, dynamic>? pending;
  bool busy = false;
  String? message;
  String category = 'all';
  Offset? dragWorld;
  PlacedItem? dragItem;
  @override
  void initState() {
    super.initState();
    state = widget.scene.roomState;
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final next = await repo.load();
      final waiting = next.familyId == null
          ? null
          : await repo.pending(next.familyId!, 'purchase');
      if (!mounted) return;
      setState(() {
        state = next;
        pending = waiting;
        preview = null;
      });
      if (next.raw['wallet'] != null) {
        widget.onWallet?.call(
          IdentityWallet.fromJson(
            Map<String, dynamic>.from(next.raw['wallet']),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => message = '商店暂未连接，请重试；待购买请求仍保留。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> details(FurnitureProduct p) async {
    final room = state!;
    final own = room.inventory.where((i) => i.sku == p.sku).length;
    final canBuy =
        !busy &&
        pending == null &&
        p.active &&
        room.familyId != null &&
        own < (p.purchaseLimit ?? 1);
    final action = await showDialog<ProductAction>(
      context: context,
      builder: (_) => FurnitureDetails(
        product: p,
        owned: own,
        canPurchase: canBuy,
        unavailable: own >= (p.purchaseLimit ?? 1)
            ? '已拥有 $own/${p.purchaseLimit ?? 1}'
            : room.familyId == null
            ? '请先加入小屋'
            : pending != null
            ? '先核对上次购买'
            : '暂不可购买',
        ownership: own == 0
            ? null
            : room.inventory
                  .where((i) => i.sku == p.sku)
                  .map(
                    (i) =>
                        '${i.source == 'test_grant'
                            ? '测试发放'
                            : i.source == 'purchase'
                            ? '购买'
                            : i.source == 'initial'
                            ? '初始赠送'
                            : '旅行'} · ${i.purchasedBy == widget.wallet.ownerId
                            ? '本人'
                            : i.purchasedBy == null
                            ? '家庭'
                            : '成员 ${i.purchasedBy!.substring(0, 6)}'}',
                  )
                  .toSet()
                  .join('、'),
      ),
    );
    if (action == null || !mounted) return;
    if (action.preview) {
      setState(() {
        preview = ShopPreview(room, p);
        scene.setFurnitureFocus(preview!.item, p, refocus: true);
        message = null;
      });
    } else {
      await purchase(p, action.quantity);
    }
  }

  Future<void> purchase(FurnitureProduct product, int quantity) async {
    final home = state?.familyId;
    if (home == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('购买${product.label}？'),
        content: Text(
          '${product.price! * quantity} ${currencyName(product.currency)}${quantity > 1 ? ' · $quantity 件' : ''}\n从本人钱包付款，进入家庭库存。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认购买'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await perform(() => repo.purchase(home, product.sku, quantity: quantity));
    }
  }

  Future<void> perform(Future<Map<String, dynamic>?> Function() action) async {
    setState(() => busy = true);
    try {
      final receipt = await action();
      if (!mounted) return;
      setState(
        () => message = receipt?['status'] == 'purchased'
            ? '购买成功，物件已进入家庭库存'
            : furnitureReason(receipt?['reason']),
      );
    } catch (_) {
      if (mounted) setState(() => message = '购买结果待核对。请重连后核对原请求，暂不进行另一笔购买。');
    } finally {
      if (mounted) await load();
    }
  }

  void dragStart(DragStartDetails e) {
    dragEnd();
    final trial = preview;
    if (!scene.geometryReady ||
        trial == null ||
        trial.product.placement != 'ground' ||
        !scene.hitsGround(e.localPosition, trial.item, trial.product)) {
      return;
    }
    dragWorld = scene.worldFromViewport(e.localPosition);
    dragItem = trial.item;
  }

  void dragUpdate(DragUpdateDetails e) {
    if (preview == null || dragWorld == null || dragItem == null) return;
    final delta = (scene.worldFromViewport(e.localPosition) - dragWorld!) * 8;
    setState(
      () => preview!.move(
        dragItem!.gx + delta.dx.round(),
        dragItem!.gy + delta.dy.round(),
      ),
    );
  }

  void tapPreview(Offset point) {
    if (preview != null && scene.hitsGhost(point)) {
      unawaited(details(preview!.product));
    }
  }

  void rotatePreview() {
    final trial = preview;
    if (trial == null) return;
    if (['art', 'window'].contains(trial.product.placement)) {
      setState(
        () => trial.item = trial.item.copy(
          slot: nextMount(trial.base.rules, trial.product, trial.item.slot),
        ),
      );
      return;
    }
    if (trial.product.placement != 'ground') return;
    dragEnd();
    setState(() {
      trial.item = trial.item.copy(
        facing: trial.item.facing == 'x' ? 'y' : 'x',
      );
      trial.move(trial.item.gx, trial.item.gy);
    });
  }

  void cancelPreview() {
    dragEnd();
    setState(() => preview = null);
  }

  Widget previewControls(ShopPreview trial) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (trial.view.rules.validate(trial.view.layout).isNotEmpty)
        Text(
          '此处无法摆放，请调整位置',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
  void dragEnd() {
    dragWorld = null;
    dragItem = null;
  }

  @override
  Widget build(BuildContext context) {
    final room = state;
    scene.roomState =
        preview != null &&
            ['wall', 'floor'].contains(preview!.product.placement)
        ? preview!.view
        : room;
    scene.draftLayout = null;
    scene.selectedInstance = null;
    scene.showGrid = false;
    scene.setGhost(preview?.item, preview?.product);
    scene.setFurnitureFocus(preview?.item, preview?.product);
    final products =
        room?.products.values
            .where(
              (p) =>
                  p.active &&
                  (!p.isTest || room.testScope) &&
                  matchesFurnitureCategory(category, p.kind),
            )
            .toList() ??
        <FurnitureProduct>[];
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(minHeight: 2),
        FurnitureCategories(
          selected: category,
          onChanged: (v) => setState(() => category = v),
        ),
        if (preview != null) previewControls(preview!),
        if (room?.testScope == true)
          const Text('隔离测试家庭 · 测试商品与余额', style: TextStyle(fontSize: 10)),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              message!,
              key: const Key('shop-message'),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        if (pending != null)
          TextButton(
            onPressed: busy
                ? null
                : () => perform(
                    () => repo.reconcile(room!.familyId!, 'purchase'),
                  ),
            child: const Text('核对原请求'),
          ),
        Expanded(
          child: room == null
              ? Center(
                  child: busy
                      ? const Text('正在读取商店…')
                      : TextButton(onPressed: load, child: const Text('重试连接')),
                )
              : FurnitureGrid(
                  key: const Key('shop-goods'),
                  products: products,
                  inventory: room.inventory,
                  onTap: details,
                ),
        ),
      ],
    );
  }
}

String currencyName(String? currency) => furnitureCurrency(currency);
