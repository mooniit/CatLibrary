import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../room_layout.dart';

typedef RoomCat = ({String name, String appearance});

/// Ground anchors use a 1000 × 1250 artboard, independent of the viewport.
class RoomScene extends FlameGame {
  RoomScene();
  List<RoomCat> cats = [];
  double zoom = 1;
  Offset pan = Offset.zero;
  ui.Image? _shell;
  ui.Image? _objects;
  final _paint = Paint()..filterQuality = FilterQuality.medium;

  // Source rectangles in the supplied 1254 × 1254 transparent atlas.
  static const _sprites = {
    'bookshelf': Rect.fromLTRB(130, 10, 547, 681),
    'bed': Rect.fromLTRB(715, 240, 1165, 614),
    'black_short': Rect.fromLTRB(89, 682, 585, 1220),
    'light_long': Rect.fromLTRB(715, 682, 1190, 1227),
  };
  static const _widths = {
    'bookshelf': 205.0,
    'bed': 150.0,
    'black_short': 95.0,
    'light_long': 90.0,
  };
  static const _catPositions = [
    GridPoint(5, 6),
    GridPoint(5, 2),
    GridPoint(3, 4),
    GridPoint(7, 4),
  ];

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  Future<void> onLoad() async {
    final loaded = await images.loadAll(['room/shell.png', 'room/objects.png']);
    _shell = loaded[0];
    _objects = loaded[1];
  }

  double get baseScale => math.max(size.x / 960, size.y / 1380);
  double get displayScale => baseScale * zoom;
  Offset get origin =>
      Offset(
        (size.x - 1000 * displayScale) / 2,
        (size.y - 1250 * displayScale) / 2,
      ) +
      pan;

  static Offset ground(GridPoint point) =>
      Offset(500 + (point.x - point.y) * 50, 548 + (point.x + point.y) * 33);

  void moveView(double nextZoom, Offset focalPoint, Offset delta) {
    final before = displayScale;
    final local = (focalPoint - delta - origin) / before;
    zoom = nextZoom.clamp(0.8, 1.6);
    final centered = Offset(
      (size.x - 1000 * displayScale) / 2,
      (size.y - 1250 * displayScale) / 2,
    );
    pan = focalPoint - local * displayScale - centered;
    _clampPan();
  }

  void _clampPan() {
    final limitX = math.max(48.0, (1000 * displayScale - size.x) / 2 + 64);
    final limitY = math.max(64.0, (1250 * displayScale - size.y) / 2 + 100);
    pan = Offset(pan.dx.clamp(-limitX, limitX), pan.dy.clamp(-limitY, limitY));
  }

  void resetView() {
    zoom = 1;
    pan = Offset.zero;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _clampPan();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final shell = _shell;
    final objects = _objects;
    if (shell == null || objects == null) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(displayScale);
    canvas.drawImageRect(
      shell,
      Rect.fromLTWH(0, 0, shell.width.toDouble(), shell.height.toDouble()),
      const Rect.fromLTWH(0, 0, 1000, 1250),
      _paint,
    );
    final items = <({String kind, GridPoint point})>[
      for (final entry in RoomLayout.defaults.entries)
        (kind: entry.key, point: entry.value),
      for (var i = 0; i < cats.length && i < _catPositions.length; i++)
        (kind: cats[i].appearance, point: _catPositions[i]),
    ]..sort((a, b) => (a.point.x + a.point.y).compareTo(b.point.x + b.point.y));
    for (final item in items) {
      final source = _sprites[item.kind];
      if (source == null) continue;
      final width = _widths[item.kind]!;
      final height = width * source.height / source.width;
      final point = ground(item.point);
      final anchor = item.kind == 'bookshelf' ? 0.88 : 0.94;
      canvas.drawImageRect(
        objects,
        source,
        Rect.fromLTWH(
          point.dx - width / 2,
          point.dy - height * anchor,
          width,
          height,
        ),
        _paint,
      );
    }
    canvas.restore();
  }
}
