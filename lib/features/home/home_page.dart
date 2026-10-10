import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;

import '../room/room_scene.dart';
import '../room/room_furniture.dart';
import '../room/furniture_store.dart';
import '../room/editor_page.dart';
import '../cats/cats_page.dart';
import '../cats/cats_repository.dart';
import '../identity/identity_repository.dart';
import '../wallet/exchange_sheet.dart';
import '../wallet/wallet_repository.dart';
import '../wallet/proxy_payment_notice.dart';
import '../repair/repair_panel.dart';
import '../settings/settings_page.dart';
import '../shop/shop_page.dart';
import '../shop/shop_repository.dart';
import '../shop/shop_preview_overlay.dart';
import '../../core/storage/app_database.dart';
import 'home_controls.dart';
import '../album/album_page.dart';
import '../travel/travel_repository.dart';
import '../../core/sync/cloud_client.dart';
import '../../core/sync/cloud_connection.dart';
import '../reminders/feeding_reminders.dart';
import '../reminders/reminder_widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onStudy,
    this.wallet,
    this.onWallet,
    this.onThemeChanged,
    this.loadCats,
    this.loadRoom,
    this.loadProxyNotices,
    this.acknowledgeProxyNotice,
    this.shopRepository,
    this.onRoomModeChanged,
    this.visible = true,
    this.reminderController,
  });
  final IdentityWallet? wallet;
  final VoidCallback onStudy;
  final ValueChanged<IdentityWallet>? onWallet;
  final Future<void> Function(ThemeMode)? onThemeChanged;
  final Future<Map<String, dynamic>> Function()? loadCats;
  final Future<FurnitureState> Function()? loadRoom;
  final Future<List<Map<String, dynamic>>> Function()? loadProxyNotices;
  final Future<void> Function(String day)? acknowledgeProxyNotice;
  final ShopRepository? shopRepository;
  final ValueChanged<bool>? onRoomModeChanged;
  final bool visible;
  final FeedingReminderController? reminderController;
  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final scene = RoomScene();
  String? catsError;
  bool loadingCats = false;
  bool hasFamily = false;
  int _request = 0;
  int _repairRequest = 0;
  double _startZoom = 1;
  Offset? _roomPointerDown;
  int _furnitureRequest = 0;
  bool loadingFurniture = true;
  String? furnitureError;
  Future<void>? _furnitureSave;
  bool _storeOpen = false;
  bool _roomToolsShown = false;
  bool _arranging = false;
  final _shopKey = GlobalKey<ShopPageState>();
  final _editorKey = GlobalKey<EditorPageState>();
  IdentityWallet? _latestWallet;
  ShopRepository? _toolsRepository;
  final _roomWidgetKey = GlobalKey();
  Offset _homePan = Offset.zero;
  double _homeZoom = RoomScene.defaultZoom;
  FurnitureState? _homeRoom;
  Timer? _roomPoll;
  bool _checkingRoom = false;
  bool _roomUpdate = false;
  CloudPhase? _previousConnection;
  FeedingReminderController? _reminders;
  bool _ownsReminders = false;
  bool _foreground = true;

  void configureReminders() {
    _reminders?.pause();
    if (_ownsReminders) _reminders?.dispose();
    final owner = widget.wallet?.ownerId;
    _ownsReminders = widget.reminderController == null;
    _reminders = owner == null
        ? null
        : widget.reminderController ??
              FeedingReminderController(
                ownerId: owner,
                rpc: widget.shopRepository?.call,
              );
    if (_reminders?.ownerId != owner) {
      _reminders = null;
    }
    _reminders?.resume();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CloudClient.connection.addListener(connectionChanged);
    configureReminders();
    unawaited(refreshCats());
    unawaited(loadFurniture());
    _roomPoll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(checkRoomUpdate()),
    );
  }

  void connectionChanged() {
    final phase = CloudClient.connection.value.phase;
    final recovered =
        phase == CloudPhase.online && _previousConnection != CloudPhase.online;
    _previousConnection = phase;
    if (mounted && recovered && widget.wallet != null && !_roomToolsShown) {
      unawaited(_reminders?.refresh());
      if (!loadingCats) unawaited(refreshCats());
      if (!loadingFurniture && furnitureError != null) {
        unawaited(loadFurniture());
      }
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallet != widget.wallet) _latestWallet = widget.wallet;
    if (oldWidget.wallet?.ownerId != widget.wallet?.ownerId ||
        oldWidget.reminderController != widget.reminderController) {
      configureReminders();
    }
    if (oldWidget.wallet?.ownerId != widget.wallet?.ownerId) {
      scene.cats = [];
      scene.confirmedRepairing = null;
      hasFamily = false;
      scene.furnishings = const RoomFurnishings();
      scene.roomState = null;
      _roomUpdate = false;
      unawaited(loadFurniture());
      unawaited(refreshCats());
    }
  }

  Future<void> loadFurniture() async {
    if (_roomToolsShown) return;
    final request = ++_furnitureRequest;
    setState(() {
      loadingFurniture = true;
      furnitureError = null;
    });
    try {
      final owner = widget.wallet?.ownerId;
      final room = await RoomFurnishings.load(owner);
      final cloud = owner == null
          ? null
          : await (widget.loadRoom?.call() ??
                ShopRepository(AppDatabase.shared, owner).load());
      if (mounted && request == _furnitureRequest) {
        setState(() {
          scene.furnishings = room;
          scene.roomState = cloud;
          _roomUpdate = false;
        });
      }
    } catch (_) {
      final owner = widget.wallet?.ownerId;
      FurnitureState? cached;
      if (owner != null && widget.loadRoom == null) {
        try {
          cached = await ShopRepository(AppDatabase.shared, owner).cached();
        } catch (_) {}
      }
      if (mounted && request == _furnitureRequest) {
        setState(() {
          if (cached != null && scene.roomState == null) {
            scene.roomState = cached;
          }
          furnitureError = cached == null
              ? '家庭布局暂未同步，点击重试；当前画面保留'
              : '离线 · 家庭布局为上次确认版本，点击重连';
        });
      }
    } finally {
      if (mounted && request == _furnitureRequest) {
        setState(() => loadingFurniture = false);
      }
    }
  }

  Future<void> checkRoomUpdate() async {
    final owner = widget.wallet?.ownerId;
    if (owner == null || _checkingRoom || _roomToolsShown) {
      return;
    }
    _checkingRoom = true;
    if (scene.roomState == null) {
      try {
        if (!loadingFurniture) await loadFurniture();
        if (catsError != null && !loadingCats) await refreshCats();
      } finally {
        _checkingRoom = false;
      }
      return;
    }
    final request = _furnitureRequest;
    try {
      final latest =
          await (widget.loadRoom?.call() ??
              ShopRepository(AppDatabase.shared, owner).load());
      if (mounted &&
          request == _furnitureRequest &&
          owner == widget.wallet?.ownerId &&
          (latest.familyId != scene.roomState?.familyId ||
              latest.version > scene.roomState!.version)) {
        setState(() => _roomUpdate = true);
      } else if (mounted &&
          request == _furnitureRequest &&
          !_roomToolsShown &&
          owner == widget.wallet?.ownerId &&
          latest.familyId == scene.roomState?.familyId &&
          latest.version == scene.roomState?.version) {
        setState(() {
          scene.roomState = latest;
          furnitureError = null;
        });
      }
    } catch (_) {
      /* The confirmed displayed layout remains; next check retries. */
    } finally {
      _checkingRoom = false;
    }
  }

  Future<void> changeFurniture(RoomFurnishings next) {
    final ownerId = widget.wallet?.ownerId;
    final request = _furnitureRequest;
    return _furnitureSave = () async {
      await next.save(ownerId);
      if (mounted &&
          request == _furnitureRequest &&
          ownerId == widget.wallet?.ownerId) {
        setState(() => scene.furnishings = next);
      }
    }();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
    if (state == AppLifecycleState.resumed) {
      _reminders?.resume();
      unawaited(refreshCats());
      if (!_roomToolsShown) unawaited(loadFurniture());
    } else {
      _reminders?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roomPoll?.cancel();
    CloudClient.connection.removeListener(connectionChanged);
    _reminders?.pause();
    if (_ownsReminders) _reminders?.dispose();
    super.dispose();
  }

  Future<void> refreshCats() async {
    final request = ++_request;
    final repairRequest = ++_repairRequest;
    if (widget.wallet == null) {
      scene.cats = [
        (id: 'preview-calico', name: '三花猫', appearance: 'black_short'),
        (id: 'preview-longhair', name: '蓝眸长毛猫', appearance: 'light_long'),
      ];
      scene.repairing = false;
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
          if (cat['traveling'] != true)
            (
              id: cat['id'] as String,
              name: cat['name'] as String,
              appearance: cat['appearance'] as String,
            ),
      ];
      setState(() {
        scene.cats = cats;
        if (repairRequest == _repairRequest) {
          scene.confirmedRepairing = result['repairing'] is bool
              ? result['repairing'] as bool
              : null;
        }
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

  Future<Map<String, dynamic>> _loadRepairState() async {
    final owner = widget.wallet!.ownerId;
    final request = ++_repairRequest;
    final repository = widget.shopRepository;
    final value =
        await (repository?.call('repair_state', const {}) ??
                _readRepairState(owner))
            .timeout(const Duration(seconds: 8));
    if (!{'none', 'active', 'completed'}.contains(value['status'])) {
      throw StateError('Unknown repair state');
    }
    if (!mounted ||
        owner != widget.wallet?.ownerId ||
        request != _repairRequest) {
      throw StateError('Repair snapshot superseded');
    }
    setState(() => scene.confirmedRepairing = value['status'] == 'active');
    return value;
  }

  Future<Map<String, dynamic>> _readRepairState(String owner) async {
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Identity changed');
    }
    return Map<String, dynamic>.from(await client.rpc('repair_state') as Map);
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

  Future<void> openStore() async {
    if (_roomToolsShown && _arranging) {
      await _editorKey.currentState?.leave();
      if (_roomToolsShown || !mounted) return;
    }
    if (_storeOpen) return;
    if (widget.wallet != null) {
      _toolsRepository =
          widget.shopRepository ??
          ShopRepository(AppDatabase.shared, widget.wallet!.ownerId);
      ++_furnitureRequest; // In-flight home loads cannot overwrite shop trial/draft.
      _homePan = scene.pan;
      _homeZoom = scene.zoom;
      _homeRoom = scene.roomState;
      setState(() {
        _storeOpen = true;
        _roomToolsShown = true;
        _arranging = false;
        scene.fitViewport = true;
        scene.zoom = 1;
        scene.forceLayout = true;
        scene.pan = Offset.zero;
      });
      widget.onRoomModeChanged?.call(true);
      return;
    }
    _storeOpen = true;
    try {
      try {
        await _furnitureSave;
      } catch (_) {
        // Legacy preferences may cache a failed write; keep the confirmed scene.
      }
      if (!mounted) return;
      if (loadingFurniture || furnitureError != null) await loadFurniture();
      if (!mounted || furnitureError != null) return;
      final wallet = widget.wallet;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => FractionallySizedBox(
          heightFactor: 0.88,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '商店',
                          style: Theme.of(c).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭商店',
                        onPressed: () => Navigator.pop(c),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FurnitureStore(
                          initial: scene.furnishings,
                          onChanged: changeFurniture,
                        ),
                        const Divider(),
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
              ],
            ),
          ),
        ),
      );
    } finally {
      _storeOpen = false;
      if (mounted) unawaited(checkRoomUpdate());
    }
  }

  void closeRoomTools(FurnitureState? latest) {
    setState(() {
      _storeOpen = false;
      _roomToolsShown = false;
      loadingFurniture = false;
      if (latest != null) furnitureError = null;
      scene.fitViewport = false;
      scene.setFurnitureFocus(null, null);
      scene.forceLayout = false;
      scene.pan = _homePan;
      scene.zoom = _homeZoom;
      scene.roomState = latest ?? _homeRoom;
      scene.draftLayout = null;
      scene.selectedInstance = null;
      scene.ghostItem = null;
      scene.ghostProduct = null;
      scene.showGrid = false;
    });
    widget.onRoomModeChanged?.call(false);
    unawaited(checkRoomUpdate());
  }

  Future<void> openArrange() async {
    if (widget.wallet == null || scene.roomState?.familyId == null) {
      info('布置', '请先创建或加入小屋。布置只显示家庭已拥有的家具。');
      return;
    }
    if (_roomToolsShown) {
      if (_arranging || _shopKey.currentState?.busy == true) return;
      closeRoomTools(_shopKey.currentState?.state);
    }
    _homePan = scene.pan;
    _homeZoom = scene.zoom;
    _homeRoom = scene.roomState;
    _toolsRepository =
        widget.shopRepository ??
        ShopRepository(AppDatabase.shared, widget.wallet!.ownerId);
    ++_furnitureRequest;
    setState(() {
      _storeOpen = true;
      _roomToolsShown = true;
      _arranging = true;
      scene.fitViewport = true;
      scene.zoom = 1;
      scene.forceLayout = true;
      scene.pan = Offset.zero;
    });
    widget.onRoomModeChanged?.call(true);
  }

  void acceptWallet(IdentityWallet wallet) {
    if (mounted) setState(() => _latestWallet = wallet);
    widget.onWallet?.call(wallet);
  }

  void openExchange() {
    final wallet = _latestWallet ?? widget.wallet;
    if (wallet == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExchangeSheet(
        wallet: wallet,
        onWallet: acceptWallet,
        repository: widget.shopRepository == null
            ? null
            : WalletRepository(
                widget.shopRepository!.database,
                wallet.ownerId,
                rpc: widget.shopRepository!.call,
              ),
      ),
    );
  }

  void closeActiveRoomTools() {
    if (_arranging) {
      unawaited(_editorKey.currentState?.leave());
    } else if (_shopKey.currentState?.busy != true) {
      closeRoomTools(_shopKey.currentState?.state);
    }
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
            CatsPage(ownerId: wallet.ownerId, onWallet: acceptWallet),
      ),
    );
    if (mounted) {
      await refreshCats();
      await _reminders?.refresh();
    }
  }

  Future<void> openAlbum() async {
    final wallet = widget.wallet;
    if (wallet == null) {
      info('相册', '连接小屋后可以查看家庭旅行回忆。');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AlbumPage(
          onWallet: acceptWallet,
          repository: TravelRepository(
            widget.shopRepository?.database ?? AppDatabase.shared,
            wallet.ownerId,
            rpc: widget.shopRepository?.call,
          ),
        ),
      ),
    );
    if (mounted) {
      await refreshCats();
      await loadFurniture();
    }
  }

  Future<void> openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          onThemeChanged: widget.onThemeChanged,
          ownerId: widget.wallet?.ownerId,
          reminderStore: _reminders?.store,
          feedingNotifications: _reminders?.notifications,
        ),
      ),
    );
    if (mounted) {
      await refreshCats();
      await _reminders?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _latestWallet ?? widget.wallet;
    scene.night = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !_roomToolsShown,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _roomToolsShown) closeActiveRoomTools();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          scene.furnitureFocusArea = _roomToolsShown
              ? Rect.fromLTRB(
                  32,
                  80,
                  constraints.maxWidth - 32,
                  (constraints.maxHeight * .48 - 64 - 24).clamp(
                    81,
                    double.infinity,
                  ),
                )
              : null;
          return Stack(
            fit: StackFit.expand,
            children: [
              const SkyBackground(),
              Positioned(
                top: _roomToolsShown ? 64 : 0,
                left: 0,
                right: 0,
                // Keep the same room canvas, extending it behind the tinted shelf.
                bottom: _roomToolsShown ? constraints.maxHeight * 0.30 : 0,
                child: Listener(
                  onPointerDown: (event) =>
                      _roomPointerDown = event.localPosition,
                  child: GestureDetector(
                    key: const Key('room-viewport'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onTapUp: _roomToolsShown && !_arranging
                        ? (event) => _shopKey.currentState?.tapPreview(
                            event.localPosition,
                          )
                        : null,
                    onDoubleTap: _roomToolsShown
                        ? null
                        : () => setState(scene.resetView),
                    onScaleStart: (event) {
                      _startZoom = scene.zoom;
                      if (_roomToolsShown && event.pointerCount == 1) {
                        final start = DragStartDetails(
                          localPosition:
                              _roomPointerDown ?? event.localFocalPoint,
                        );
                        if (_arranging) {
                          _editorKey.currentState?.dragStart(start);
                        } else {
                          _shopKey.currentState?.dragStart(start);
                        }
                      }
                    },
                    onScaleUpdate: (event) => setState(() {
                      final dragging = _arranging
                          ? _editorKey.currentState?.dragItem != null
                          : _shopKey.currentState?.dragItem != null;
                      if (_roomToolsShown &&
                          event.pointerCount == 1 &&
                          dragging) {
                        final update = DragUpdateDetails(
                          globalPosition: event.focalPoint,
                          delta: event.focalPointDelta,
                          localPosition: event.localFocalPoint,
                        );
                        if (_arranging) {
                          _editorKey.currentState?.dragUpdate(update);
                        } else {
                          _shopKey.currentState?.dragUpdate(update);
                        }
                      } else {
                        if (event.pointerCount > 1 && dragging) {
                          if (_arranging) {
                            _editorKey.currentState?.dragEnd();
                          } else {
                            _shopKey.currentState?.dragEnd();
                          }
                        }
                        scene.moveView(
                          _startZoom * event.scale,
                          event.localFocalPoint,
                          event.focalPointDelta,
                        );
                      }
                    }),
                    onScaleEnd: (_) {
                      if (_arranging) {
                        _editorKey.currentState?.dragEnd();
                      } else if (_roomToolsShown) {
                        _shopKey.currentState?.dragEnd();
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Semantics(
                          label: '小屋家具陈设，拖动查看，双指缩放，双击回到初始视角。',
                          child: GameWidget(
                            key: _roomWidgetKey,
                            game: scene,
                            loadingBuilder: (_) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            errorBuilder: (_, _) =>
                                const Center(child: Text('猫窝素材加载失败，请重新打开页面')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_roomToolsShown && wallet != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: constraints.maxHeight * 0.52,
                  child: Material(
                    key: const Key('room-tools-shelf'),
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.96),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _arranging
                        ? EditorPage(
                            key: _editorKey,
                            repository: _toolsRepository!,
                            scene: scene,
                            onExit: () =>
                                closeRoomTools(_editorKey.currentState?.state),
                          )
                        : ShopPage(
                            key: _shopKey,
                            wallet: wallet,
                            onWallet: acceptWallet,
                            repository: _toolsRepository,
                            scene: scene,
                          ),
                  ),
                ),
              // Handles stay above the shelf when a preview overlaps its edge.
              if (_roomToolsShown)
                Positioned(
                  top: 64,
                  left: 0,
                  right: 0,
                  bottom: constraints.maxHeight * 0.30,
                  child: ShopPreviewOverlay(
                    scene: scene,
                    onRotate: () {
                      if (_arranging) {
                        _editorKey.currentState?.rotatePreview();
                      } else {
                        _shopKey.currentState?.rotatePreview();
                      }
                    },
                    onCancel: () {
                      if (_arranging) {
                        _editorKey.currentState?.cancelPreview();
                      } else {
                        _shopKey.currentState?.cancelPreview();
                      }
                    },
                  ),
                ),
              if (_roomToolsShown)
                Positioned(
                  top: 68,
                  left: 12,
                  child: Row(
                    children: [
                      RoomActionButton(
                        label: _arranging ? '离开并保留草稿' : '关闭商店',
                        icon: Icons.close,
                        onPressed: closeActiveRoomTools,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _arranging ? '布置' : '商店',
                        key: const Key('room-mode-label'),
                      ),
                    ],
                  ),
                ),
              if (wallet != null && !_roomToolsShown)
                ProxyPaymentNotice(
                  key: ValueKey('notice-${wallet.ownerId}'),
                  ownerId: wallet.ownerId,
                  load: widget.loadProxyNotices,
                  acknowledge: widget.acknowledgeProxyNotice,
                ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: HomeWallet(
                  key: const Key('persistent-home-wallet'),
                  wallet: wallet,
                  onExchange: openExchange,
                ),
              ),
              Positioned(
                top: 68,
                right: 12,
                child: HomeMenu(
                  key: const Key('persistent-home-menu'),
                  onCats: openCats,
                  onStore: openStore,
                  onArrange: openArrange,
                  onAlbum: openAlbum,
                  onSettings: openSettings,
                ),
              ),
              if (!_roomToolsShown)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (wallet != null && _reminders != null)
                        FeedingReminderBanner(
                          key: ValueKey('feeding-${wallet.ownerId}'),
                          controller: _reminders!,
                          onOpen: openCats,
                          visible:
                              widget.visible &&
                              _foreground &&
                              (ModalRoute.of(context)?.isCurrent ?? true),
                        ),
                      if (scene.pan.distance > 1 ||
                          scene.zoom != RoomScene.defaultZoom)
                        RoomActionButton(
                          label: '回到初始视角',
                          icon: Icons.center_focus_strong_outlined,
                          onPressed: () => setState(scene.resetView),
                        ),
                      if (wallet != null)
                        RepairPanel(
                          key: ValueKey('repair-${wallet.ownerId}'),
                          ownerId: wallet.ownerId,
                          load: _loadRepairState,
                        ),
                    ],
                  ),
                ),
              if (!_roomToolsShown)
                Positioned(
                  top: 68,
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
                            status('交互预览 · 家具陈设', null)
                          else
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: HomeConnectionStatus(
                                cached: wallet.cached,
                                onTap: openSettings,
                              ),
                            ),
                          if ((wallet?.miaoCoins ?? 0) < 0)
                            status('喵喵币欠款 ${-wallet!.miaoCoins}', null),
                          if (loadingCats)
                            status('正在同步猫咪…', null)
                          else if (catsError != null)
                            status(catsError!, refreshCats)
                          else if (wallet != null && scene.cats.isEmpty)
                            status(hasFamily ? '认识第一只猫咪' : '创建或加入小屋', openCats),
                          if (furnitureError != null)
                            status(furnitureError!, loadFurniture),
                          if (_roomUpdate)
                            status('家庭布局已更新，点击刷新查看', loadFurniture),
                          if (wallet != null &&
                              scene.roomState?.configured == false)
                            status('陈设预览 · 暂未取得家庭布局', null),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                onTap == null
                    ? Icons.info_outline_rounded
                    : Icons.arrow_circle_right_outlined,
                size: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
