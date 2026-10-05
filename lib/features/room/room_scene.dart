import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'room_furniture.dart';
import 'lunar_room.dart';

typedef RoomCat = ({String name, String appearance});

/// The frozen room-standard-v1 is the only room camera and geometry.
class RoomScene extends FlameGame {
  RoomScene();
  static const defaultZoom = 1.25;
  List<RoomCat> cats = [];
  RoomFurnishings furnishings = const RoomFurnishings();
  double zoom = defaultZoom;
  Offset pan = Offset.zero;
  final _artworks = <ArtworkStyle, ui.Image>{};
  LunarRoom? _lunar;
  bool night = false;

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  Future<void> onLoad() async {
    for (final style in ArtworkStyle.values) {
      _artworks[style] = await images.load(style.asset);
    }
    _lunar = await LunarRoom.load(images.load);
  }

  Size get artboard => const Size(1080, 1073);
  double get baseScale =>
      math.min(size.x / 1120, (size.y - 112).clamp(1, double.infinity) / 1113);
  double get displayScale => baseScale * zoom;
  Offset get origin =>
      Offset(
        (size.x - artboard.width * displayScale) / 2,
        (size.y - artboard.height * displayScale) / 2 + 48,
      ) +
      pan;

  void moveView(double nextZoom, Offset focalPoint, Offset delta) {
    final local = (focalPoint - delta - origin) / displayScale;
    zoom = nextZoom.clamp(0.8, 1.6);
    final centered = Offset(
      (size.x - artboard.width * displayScale) / 2,
      (size.y - artboard.height * displayScale) / 2 + 48,
    );
    pan = focalPoint - local * displayScale - centered;
    _clampPan();
  }

  void _clampPan() {
    final limitX = math.max(
      48.0,
      (artboard.width * displayScale - size.x) / 2 + 64,
    );
    final limitY = math.max(
      64.0,
      (artboard.height * displayScale - size.y) / 2 + 100,
    );
    pan = Offset(pan.dx.clamp(-limitX, limitX), pan.dy.clamp(-limitY, limitY));
  }

  void resetView() {
    zoom = defaultZoom;
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
    if (_lunar == null) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(displayScale);
    _lunar!.render(canvas, furnishings, night, _artworks);
    canvas.restore();
  }
}
