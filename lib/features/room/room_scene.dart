import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'room_furniture.dart';
import 'lunar_room.dart';
import 'souvenir_sculpture.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'layout_draft.dart';
import '../shop/shop_repository.dart';
import 'cat_behavior.dart';

export 'cat_behavior.dart' show RoomCat;

/// The frozen room-standard-v1 is the only room camera and geometry.
class RoomScene extends FlameGame {
  RoomScene({this.fitViewport = false, this.forceLayout = false});
  bool fitViewport;
  bool forceLayout;
  static const defaultZoom = 1.25;
  final catColony = CatColony();
  List<RoomCat> _cats = const [];
  List<RoomCat> get cats => _cats;
  set cats(List<RoomCat> value) {
    _cats = List.unmodifiable(value);
    catColony.sync(_cats);
  }

  // Unknown live state never implies that care during repair is allowed.
  bool repairing = true;
  RoomFurnishings furnishings = const RoomFurnishings();
  double zoom = defaultZoom;
  Offset pan = Offset.zero;
  final _artworks = <ArtworkStyle, ui.Image>{};
  LunarRoom? _lunar;
  final _themes = <String, LunarRoom>{};
  FurnitureState? roomState;
  RoomLayout? draftLayout;
  String? selectedInstance;
  PlacedItem? ghostItem;
  FurnitureProduct? ghostProduct;
  Rect? furnitureFocusArea;
  PlacedItem? _focusItem;
  FurnitureProduct? _focusProduct;

  void setFurnitureFocus(
    PlacedItem? item,
    FurnitureProduct? product, {
    bool refocus = false,
  }) {
    if (item == null || product == null) {
      _focusItem = null;
      _focusProduct = null;
    } else if (refocus) {
      _focusItem = item;
      _focusProduct = product;
      _applyInitialFocus();
    } else {
      return;
    }
    notifyPreviewChanged();
  }

  Rect placedViewportBounds(PlacedItem item, FurnitureProduct product) {
    final bounds = _lunar!.placedSpriteBounds(item, product, _themes);
    return Rect.fromLTRB(
      origin.dx + bounds.left * displayScale,
      origin.dy + bounds.top * displayScale,
      origin.dx + bounds.right * displayScale,
      origin.dy + bounds.bottom * displayScale,
    );
  }

  void _applyInitialFocus() {
    final area = furnitureFocusArea;
    if (!geometryReady || area == null || _focusItem == null) return;
    final bounds = _lunar!.placedSpriteBounds(
      _focusItem!,
      _focusProduct!,
      _themes,
    );
    final scale = math.min(
      baseScale,
      math.min(area.width / bounds.width, area.height / bounds.height),
    );
    zoom = scale / baseScale;
    pan = area.center - bounds.center * scale - _centeredOrigin;
    // Consumed once. Subsequent pan, zoom, rotation and slot changes stay free.
    _focusItem = null;
    _focusProduct = null;
  }

  final previewChanges = ValueNotifier<int>(0);
  bool _previewNotificationQueued = false;
  void notifyPreviewChanged({bool cleared = false}) {
    if (ghostItem == null && !cleared) return;
    if (_previewNotificationQueued) return;
    _previewNotificationQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _previewNotificationQueued = false;
      previewChanges.value++;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void setGhost(PlacedItem? item, FurnitureProduct? product) {
    if (identical(item, ghostItem) && identical(product, ghostProduct)) return;
    ghostItem = item;
    ghostProduct = product;
    notifyPreviewChanged(cleared: true);
  }

  Rect? get ghostBounds {
    if (!geometryReady || ghostItem == null || ghostProduct == null) {
      return null;
    }
    return placedViewportBounds(ghostItem!, ghostProduct!);
  }

  bool hitsGhost(Offset point) {
    if (ghostBounds == null) return false;
    return ghostProduct!.placement == 'ground'
        ? hitsGround(point, ghostItem!, ghostProduct!)
        : ghostBounds!.contains(point);
  }

  bool showGrid = false;
  bool _geometryReady = false;
  bool get geometryReady => _geometryReady;
  bool night = false;

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  Future<void> onLoad() async {
    for (final style in ArtworkStyle.values) {
      _artworks[style] = await images.load(style.asset);
    }
    _lunar = await LunarRoom.load(images.load);
    for (final value
        in jsonDecode(
              await rootBundle.loadString('assets/data/souvenir-products.json'),
            )
            as List) {
      await SouvenirSculpture.prepare(
        FurnitureProduct.fromJson(Map<String, dynamic>.from(value)),
        _lunar!.project,
      );
    }
    _themes['lunar'] = _lunar!;
    for (final theme in ['wood', 'royal']) {
      _themes[theme] = await LunarRoom.load(images.load, theme: theme);
    }
    _geometryReady = true;
    _applyInitialFocus();
    notifyPreviewChanged();
  }

  Size get artboard => const Size(1080, 1073);
  // Custom room drawing occurs outside Flame's camera transformation.
  // Use the actual canvas, including while the camera is still mounting.
  double get baseScale => math.min(
    canvasSize.x / 1120,
    (canvasSize.y - (fitViewport ? 0 : 112)).clamp(1, double.infinity) / 1113,
  );
  double get displayScale => baseScale * zoom;

  Offset get _centeredOrigin => Offset(
    (canvasSize.x - artboard.width * displayScale) / 2,
    (canvasSize.y - artboard.height * displayScale) / 2 +
        (fitViewport ? 0 : 48),
  );
  Offset get origin => _centeredOrigin + pan;

  void moveView(double nextZoom, Offset focalPoint, Offset delta) {
    final local = (focalPoint - delta - origin) / displayScale;
    zoom = nextZoom.clamp(fitViewport ? 0.2 : 0.8, fitViewport ? 2.5 : 1.6);
    pan = focalPoint - local * displayScale - _centeredOrigin;
    if (!fitViewport) _clampPan();
    notifyPreviewChanged();
  }

  void _clampPan() {
    final limitX = math.max(
      48.0,
      (artboard.width * displayScale - canvasSize.x) / 2 + 64,
    );
    final limitY = math.max(
      64.0,
      (artboard.height * displayScale - canvasSize.y) / 2 + 100,
    );
    pan = Offset(pan.dx.clamp(-limitX, limitX), pan.dy.clamp(-limitY, limitY));
  }

  void resetView() {
    zoom = defaultZoom;
    pan = Offset.zero;
  }

  Offset projectWorld(num x, num y, [num z = 0]) => _lunar!.project(x, y, z);
  bool hitsGround(Offset point, PlacedItem item, FurnitureProduct product) =>
      _lunar!.hitsGround((point - origin) / displayScale, item, product);
  Offset worldFromViewport(Offset point) {
    final p = (point - origin) / displayScale;
    // Inverse of the same frozen camera used by rendering.
    final c = _lunar!.camera,
        o = c['origin'] as List,
        bx = c['bx'] as List,
        by = c['by'] as List;
    final a = p.dx - o[0], b = p.dy - o[1], det = bx[0] * by[1] - by[0] * bx[1];
    return Offset((a * by[1] - by[0] * b) / det, (bx[0] * b - a * bx[1]) / det);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!fitViewport) _clampPan();
    notifyPreviewChanged();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_lunar == null) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(displayScale);
    final state = roomState;
    if (state != null && (state.configured || forceLayout)) {
      _lunar!.renderPlaced(
        canvas,
        draftLayout ?? state.layout,
        state.products,
        state.inventory,
        _themes,
        night,
        _artworks,
        selected: selectedInstance,
      );
    } else {
      _lunar!.render(canvas, furnishings, night, _artworks);
    }
    if (selectedInstance == null &&
        ghostItem != null &&
        ghostProduct != null &&
        !['wall', 'floor'].contains(ghostProduct!.placement)) {
      _lunar!.renderGhost(
        canvas,
        ghostItem!,
        ghostProduct!,
        _themes,
        night,
        _artworks,
      );
    }
    if (showGrid) {
      final line = Paint()
        ..color = const Color(0x906080a0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (var i = 0; i <= 8; i++) {
        canvas.drawLine(
          _lunar!.project(i / 8, 0),
          _lunar!.project(i / 8, 1),
          line,
        );
        canvas.drawLine(
          _lunar!.project(0, i / 8),
          _lunar!.project(1, i / 8),
          line,
        );
      }
      final layout = draftLayout ?? state?.layout;
      final item = layout?.items
          .where((i) => i.instanceId == selectedInstance)
          .firstOrNull;
      final inventory = state?.inventory
          .where((i) => i.id == selectedInstance)
          .firstOrNull;
      final product = state?.products[inventory?.sku];
      if (item != null && product?.placement == 'ground') {
        final valid = state!.rules.validate(layout!).isEmpty;
        for (final cell in product!.cells(item.facing)) {
          final x = (cell.$1 + item.gx) / 8, y = (cell.$2 + item.gy) / 8;
          final path = Path()
            ..addPolygon([
              _lunar!.project(x, y),
              _lunar!.project(x + .125, y),
              _lunar!.project(x + .125, y + .125),
              _lunar!.project(x, y + .125),
            ], true);
          canvas.drawPath(
            path,
            Paint()
              ..color = valid
                  ? const Color(0x90698eaf)
                  : const Color(0x90bc5960),
          );
          canvas.drawPath(path, line);
        }
      }
    }
    canvas.restore();
  }
}
