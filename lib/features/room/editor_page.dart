import 'dart:async';
import 'dart:convert';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../shop/shop_repository.dart';
import 'layout_draft.dart';
import 'room_scene.dart';
import 'furniture_catalog_widgets.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.repository,
    required this.scene,
    this.onExit,
  });
  final ShopRepository repository;
  final RoomScene scene;
  final VoidCallback? onExit;
  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  late final scene = widget.scene;
  late final repo = widget.repository;
  FurnitureState? state;
  LayoutDraft? draft;
  String token = furnitureRequestId();
  bool busy = false, paused = true, foreground = true, pendingSave = false;
  String message = '正在核对家庭布局…';
  String? replacing;
  Timer? renewal;
  Stopwatch leaseClock = Stopwatch();
  Duration leaseRemaining = Duration.zero;
  Future<void> persistence = Future.value();
  Offset? dragWorld;
  PlacedItem? dragItem;
  String category = 'all';
  bool personalInventory = false;
  List<InventoryInstance> get visibleInventory =>
      state?.inventory
          .where((i) => !personalInventory || i.belongsTo(repo.ownerId))
          .toList() ??
      [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(connect());
  }

  @override
  void dispose() {
    renewal?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get editable =>
      !busy &&
      !paused &&
      !pendingSave &&
      foreground &&
      leaseClock.elapsed < leaseRemaining;
  String get family => state!.familyId!;
  Future<void> persist() {
    final current = draft;
    if (current == null || state?.familyId == null) return Future.value();
    current.replacing = replacing;
    final payload = jsonDecode(current.encode()) as Map<String, dynamic>;
    final home = family;
    // Serialize writes, including preview, so a slow older write cannot win.
    persistence = persistence
        .catchError((_) {})
        .then(
          (_) => repo.database.putFurnitureLocal(
            repo.ownerId,
            home,
            'draft',
            payload,
          ),
        );
    return persistence;
  }

  void updateScene() {
    if (state == null) return;
    scene.roomState = state;
    scene.draftLayout = draft?.preview == null
        ? draft?.layout
        : draft?.candidate(replacing: replacing);
    scene.selectedInstance = draft?.preview?.instanceId;
    final selected = draft?.preview;
    final sku = state!.inventory
        .where((i) => i.id == selected?.instanceId)
        .firstOrNull
        ?.sku;
    scene.setGhost(selected, state!.products[sku]);
    scene.setFurnitureFocus(selected, state!.products[sku]);
    scene.showGrid = true;
  }

  Future<void> connect() async {
    if (busy) return;
    setState(() {
      busy = true;
      paused = true;
    });
    renewal?.cancel();
    try {
      await persistence;
      final known = state ?? await repo.cached();
      var receipt = known?.familyId == null
          ? null
          : await repo.reconcile(known!.familyId!, 'save');
      var latest = await repo.load();
      if (latest.familyId == null) throw StateError('请先加入小屋');
      if (known?.familyId != latest.familyId) {
        receipt = await repo.reconcile(latest.familyId!, 'save');
      }
      latest = await repo
          .load(); // Original receipt never substitutes for latest family state.
      var local = await repo.draft(latest.familyId!);
      final saved =
          receipt ?? await repo.pending(latest.familyId!, 'save_receipt');
      if (local != null &&
          saved?['status'] == 'saved' &&
          local.baseVersion + 1 == saved!['version'] &&
          local.preview == null &&
          jsonEncode(local.layout.toJson()) ==
              jsonEncode(RoomLayout.fromJson(saved['saved_layout']).toJson())) {
        local = LayoutDraft(local.layout, saved['version']);
        await repo.storeDraft(latest.familyId!, local);
      }
      if (!mounted) return;
      setState(() {
        state = latest;
        draft = local ?? LayoutDraft(latest.layout, latest.version);
        pendingSave = false;
        replacing = local?.replacing;
        message = receipt?['status'] == 'saved'
            ? '已核对：保存成功于版本 ${receipt!['version']}'
            : receipt?['status'] == 'rejected'
            ? furnitureReason(receipt!['reason'])
            : '草稿已保留';
        updateScene();
      });
      if (draft!.baseVersion != latest.version) {
        setState(
          () => message += '；家庭已有版本 ${latest.version}，请查看最新布局后决定，原草稿未覆盖。',
        );
      } else {
        final grant = await repo.editor('acquire', token);
        if (!mounted) {
          if (grant['status'] == 'acquired') {
            unawaited(repo.editor('release', token));
          }
          return;
        }
        if (grant['status'] == 'acquired') {
          final granted = FurnitureState.fromJson(grant);
          if (granted.version != draft!.baseVersion) {
            await repo.editor('release', token);
            setState(() {
              state = granted;
              message = '取得编辑权前家庭版本已更新；草稿保留，请查看最新布局。';
              updateScene();
            });
          } else {
            state = granted;
            setLease(grant);
            setState(() {
              paused = false;
              message = '正在编辑 · 单品确认只加入草稿';
              updateScene();
            });
            startRenewal();
          }
        } else {
          setState(() => message = furnitureReason(grant['reason']));
        }
      }
    } catch (error) {
      if (state == null) {
        final cached = await repo.cached();
        final local = cached?.familyId == null
            ? null
            : await repo.draft(cached!.familyId!);
        if (mounted && cached != null) {
          setState(() {
            state = cached;
            draft = local ?? LayoutDraft(cached.layout, cached.version);
            replacing = local?.replacing;
            updateScene();
          });
        }
      }
      if (mounted) {
        setState(() {
          paused = true;
          message = '连接或核对未完成，编辑暂停，草稿已保留。请重试核对。';
        });
      }
      if (state?.familyId != null) {
        pendingSave = await repo.pending(family, 'save') != null;
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void setLease(Map<String, dynamic> raw) {
    leaseRemaining = DateTime.parse(
      raw['lock_until'],
    ).difference(DateTime.parse(raw['server_time']));
    leaseClock = Stopwatch()..start();
  }

  void startRenewal() {
    renewal?.cancel();
    renewal = Timer.periodic(
      Duration(seconds: state!.raw['renewal_seconds']),
      (_) => unawaited(renew()),
    );
  }

  Future<void> renew() async {
    if (!foreground || busy || paused) return;
    try {
      final grant = await repo.editor('renew', token);
      if (!mounted) return;
      if (grant['status'] != 'acquired') {
        setState(() {
          paused = true;
          message = furnitureReason(grant['reason']);
        });
      } else if (grant['version'] != draft!.baseVersion) {
        setState(() {
          paused = true;
          message = '家庭版本已变化，草稿已保留。请查看最新布局。';
        });
      } else {
        setLease(grant);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          paused = true;
          message = '连接已中断，编辑暂停，草稿已保留。重连先核对原保存请求。';
        });
      }
    }
    if (paused) {
      renewal?.cancel();
      await persist();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      renewal?.cancel();
      paused = true;
      unawaited(persist());
    } else {
      unawaited(connect());
    }
  }

  Future<void> change(VoidCallback operation) async {
    if (!editable) return;
    setState(() {
      operation();
      updateScene();
    });
    try {
      await persist();
    } catch (_) {
      if (mounted) {
        setState(() {
          paused = true;
          message = '草稿未能写入本机，请保留此页后重试保存草稿。';
        });
      }
    }
  }

  void select(
    InventoryInstance instance, {
    PlacedItem? placed,
    String? replace,
  }) {
    final p = state!.products[instance.sku]!;
    unawaited(
      change(() {
        replacing = replace;
        final slots = state!.rules.slots.entries
            .where((e) => e.value == p.placement)
            .map((e) => e.key)
            .toList();
        draft!.preview =
            placed ??
            PlacedItem(
              instance.id,
              slot: p.placement == 'ground' ? null : slots.first,
              artwork: p.artwork ?? 'starry',
            );
        message =
            '选中${p.label}${instance.sourceCatName == null ? '' : ' · 来自${instance.sourceCatName}的${instance.sourceDestination}旅行'}，预览尚未确认到草稿';
        scene.setFurnitureFocus(draft!.preview, p, refocus: true);
      }),
    );
  }

  Future<void> selectOwned(FurnitureProduct product) async {
    if (!editable) return;
    final options = visibleInventory
        .where((i) => i.sku == product.sku)
        .toList();
    InventoryInstance? chosen;
    if (options.length == 1 && product.kind != 'souvenir') {
      chosen = options.single;
    } else {
      chosen = await showModalBottomSheet<InventoryInstance>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final i in options)
                ListTile(
                  title: Text(product.label),
                  subtitle: Text(
                    '${i.source == 'test_grant' ? '测试发放 · ${i.belongsTo(repo.ownerId) ? '个人仓库' : '家庭仓库'}\n' : ''}${i.sourceCatName == null ? '' : '${i.sourceCatName} · ${i.sourceDestination}\n'}${draft!.layout.items.any((p) => p.instanceId == i.id) ? '已摆放 · ${i.id.substring(0, 8)}' : '库存 · ${i.id.substring(0, 8)}'}',
                  ),
                  onTap: () => Navigator.pop(c, i),
                ),
            ],
          ),
        ),
      );
    }
    if (chosen != null && mounted) {
      select(
        chosen,
        placed: draft!.layout.items
            .where((p) => p.instanceId == chosen!.id)
            .firstOrNull,
      );
    }
  }

  Future<void> chooseReplacement(PlacedItem original) async {
    final oldInstance = state!.inventory.firstWhere(
      (i) => i.id == original.instanceId,
    );
    final oldProduct = state!.products[oldInstance.sku]!;
    final options = visibleInventory
        .where(
          (i) =>
              i.id != original.instanceId &&
              state!.products[i.sku]?.kind == oldProduct.kind &&
              !draft!.layout.items.any((p) => p.instanceId == i.id),
        )
        .toList();
    final chosen = await showModalBottomSheet<InventoryInstance>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择库存中的另一款')),
            if (options.isEmpty) const ListTile(title: Text('暂无可用于换款的库存')),
            for (final i in options)
              ListTile(
                title: Text(state!.products[i.sku]!.label),
                onTap: () => Navigator.pop(c, i),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      select(
        chosen,
        placed: original.copy(
          instanceId: chosen.id,
          artwork: state!.products[chosen.sku]!.artwork,
        ),
        replace: original.instanceId,
      );
    }
  }

  void dragStart(DragStartDetails e) {
    if (!scene.geometryReady) return;
    final item = draft?.preview;
    if (!editable ||
        item == null ||
        state
                ?.products[state!.inventory
                    .firstWhere((i) => i.id == item.instanceId)
                    .sku]
                ?.placement !=
            'ground') {
      return;
    }
    final product =
        state!.products[state!.inventory
            .firstWhere((i) => i.id == item.instanceId)
            .sku]!;
    if (!scene.hitsGround(e.localPosition, item, product)) return;
    dragWorld = scene.worldFromViewport(e.localPosition);
    dragItem = item;
  }

  void dragUpdate(DragUpdateDetails e) {
    if (!editable || dragWorld == null || dragItem == null) return;
    final delta = (scene.worldFromViewport(e.localPosition) - dragWorld!) * 8;
    setState(() {
      draft!.preview = dragItem!.copy(
        gx: dragItem!.gx + delta.dx.round(),
        gy: dragItem!.gy + delta.dy.round(),
      );
      updateScene();
    });
  }

  void dragEnd() {
    dragWorld = null;
    dragItem = null;
    unawaited(persist());
  }

  void rotatePreview() {
    final item = draft?.preview;
    if (!editable || item == null) return;
    final p =
        state!.products[state!.inventory
            .firstWhere((i) => i.id == item.instanceId)
            .sku]!;
    unawaited(
      change(
        () => draft!.preview = p.placement == 'ground'
            ? item.copy(facing: item.facing == 'x' ? 'y' : 'x')
            : item.copy(slot: nextMount(state!.rules, p, item.slot)),
      ),
    );
  }

  void cancelPreview() {
    if (!editable) return;
    unawaited(
      change(() {
        draft!.cancelPreview();
        replacing = null;
      }),
    );
  }

  Future<void> save() async {
    if (!editable || draft?.preview != null) return;
    final errors = state!.rules.validate(draft!.layout);
    if (errors.isNotEmpty) {
      setState(() => message = errors.join('；'));
      return;
    }
    setState(() => busy = true);
    Map<String, dynamic>? received;
    try {
      await persistence;
      final receipt = await repo.save(family, token, draft!);
      received = receipt;
      if (!mounted) return;
      if (receipt['status'] == 'saved') {
        draft = LayoutDraft(draft!.layout, receipt['version']);
        await persist();
        final latest = await repo.load();
        if (!mounted) return;
        setState(() {
          state = latest;
          if (latest.version != draft!.baseVersion) {
            paused = true;
            message =
                '保存成功于版本 ${receipt['version']}；随后家庭已有版本 ${latest.version}，请查看最新布局。';
          } else {
            message = '保存成功 · 家庭版本 ${receipt['version']}';
          }
          updateScene();
        });
      } else {
        setState(() {
          paused = true;
          message = furnitureReason(receipt['reason']);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          paused = true;
          pendingSave = received == null;
          message = received?['status'] == 'saved'
              ? '保存成功于版本 ${received!['version']}，最新布局暂未读取，请重连核对。'
              : '保存结果待核对，草稿已保留。重连后先核对原请求。';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> inspectLatest() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final latest = await repo.load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('最新家庭版本 ${latest.version}'),
          content: SizedBox(
            width: 340,
            height: 360,
            child: GameWidget(
              game: RoomScene(fitViewport: true)..roomState = latest,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('保留原草稿'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => message = '最新布局暂未读取，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restart() async {
    if (busy || pendingSave) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('放弃原草稿并从最新布局重新开始？'),
        content: const Text('原草稿不会自动合并到他人的新布局。此操作将明确删除本机原草稿。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('保留草稿'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('放弃并重新开始'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await persistence;
    await repo.discardDraft(family);
    draft = null;
    await connect();
  }

  Future<void> leave() async {
    if (busy) return;
    try {
      await persist();
      await persistence;
      renewal?.cancel();
      try {
        await repo.editor('release', token);
      } catch (_) {
        /* The lease expires on the server. */
      }
      if (mounted) {
        if (widget.onExit != null) {
          widget.onExit!();
        } else {
          Navigator.pop(context);
        }
      }
    } catch (_) {
      if (mounted) setState(() => message = '草稿未写入本机，暂不离开，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    updateScene();
    scene.night = Theme.of(context).brightness == Brightness.dark;
    final current = draft?.preview, room = state;
    final p = current == null || room == null
        ? null
        : room.products[room.inventory
              .firstWhere((i) => i.id == current.instanceId)
              .sku];
    final errors = current == null || room == null
        ? <String>[]
        : room.rules.validate(draft!.candidate(replacing: replacing));
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 0.60,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (busy) const LinearProgressIndicator(),
                  FurnitureCategories(
                    selected: category,
                    onChanged: (v) => setState(() => category = v),
                  ),
                  if (message != '正在编辑 · 单品确认只加入草稿')
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Text(
                        message,
                        key: const Key('editor-message'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  if (paused && !busy)
                    Wrap(
                      children: [
                        FurnitureTool(
                          label: '重连核对／获取编辑权',
                          icon: Icons.sync_rounded,
                          onPressed: connect,
                        ),
                        FurnitureTool(
                          label: '查看最新布局',
                          icon: Icons.visibility_outlined,
                          onPressed: inspectLatest,
                        ),
                        FurnitureTool(
                          label: '放弃草稿并重新开始',
                          icon: Icons.restart_alt_rounded,
                          onPressed: pendingSave ? null : restart,
                        ),
                      ],
                    ),
                  if (current != null && p != null) ...[
                    if (errors.isNotEmpty)
                      Text(
                        errors.join('；'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        FurnitureTool(
                          label: '收起',
                          icon: Icons.inventory_2_outlined,
                          onPressed: editable
                              ? () => change(() {
                                  draft!.stow(replacing ?? current.instanceId);
                                  replacing = null;
                                })
                              : null,
                        ),
                        if (draft!.layout.items.any(
                          (i) => i.instanceId == current.instanceId,
                        ))
                          FurnitureTool(
                            label: '换款',
                            icon: Icons.swap_horiz_rounded,
                            onPressed: editable
                                ? () => chooseReplacement(current)
                                : null,
                          ),
                        FurnitureTool(
                          label: '确认',
                          icon: Icons.check_rounded,
                          onPressed: editable && errors.isEmpty
                              ? () => change(() {
                                  draft!.confirm(
                                    room!.rules,
                                    replacing: replacing,
                                  );
                                  replacing = null;
                                  message = '已确认到草稿，尚未保存到家庭';
                                })
                              : null,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: room == null
                ? const SizedBox()
                : FurnitureGrid(
                    key: const Key('editor-inventory'),
                    ownedOnly: true,
                    products: room.products.values
                        .where(
                          (p) =>
                              matchesFurnitureCategory(category, p.kind) &&
                              visibleInventory.any((i) => i.sku == p.sku),
                        )
                        .toList(),
                    inventory: visibleInventory,
                    layout: draft!.layout,
                    onTap: selectOwned,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  personalInventory ? '个人仓库' : '家庭仓库',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                IconButton(
                  key: const Key('personal-inventory'),
                  tooltip: '个人仓库',
                  isSelected: personalInventory,
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  onPressed: () => setState(() => personalInventory = true),
                ),
                IconButton(
                  key: const Key('family-inventory'),
                  tooltip: '家庭仓库',
                  isSelected: !personalInventory,
                  icon: const Icon(Icons.cottage_outlined),
                  selectedIcon: const Icon(Icons.cottage),
                  onPressed: () => setState(() => personalInventory = false),
                ),
                const Spacer(),
                if (room != null)
                  Tooltip(
                    message:
                        '草稿基于版本 ${draft!.baseVersion} · 最新家庭版本 ${room.version}',
                    child: Icon(
                      Icons.cloud_done_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: '保存到家庭',
                  onPressed: editable && current == null ? save : null,
                  icon: const Icon(Icons.save_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String slotLabel(String slot) =>
    const {
      'window-left': '左窗',
      'window-right': '右窗',
      'art-left-back': '左墙画位1',
      'art-left-front': '左墙画位2',
      'art-right-back': '右墙画位1',
      'art-right-front': '右墙画位2',
      'rug': '中央地毯',
      'wall': '整体墙面',
      'floor': '整体地板',
    }[slot] ??
    slot;
