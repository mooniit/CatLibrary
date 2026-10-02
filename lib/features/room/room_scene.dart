import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../room_layout.dart';
import 'room_furniture.dart';

typedef RoomCat = ({String name, String appearance});

/// One 1000 × 1250 artboard defines walls, floor and furniture contacts.
class RoomScene extends FlameGame {
  RoomScene();
  List<RoomCat> cats = [];
  RoomFurnishings furnishings = const RoomFurnishings();
  double zoom = 1;
  Offset pan = Offset.zero;
  ui.Image? _floor;
  final _walls = <WallStyle, ui.Image>{};
  final _furniture = <FurnitureStyle, ui.Image>{};
  final _artworks = <ArtworkStyle, ui.Image>{};
  final _paint = Paint()..filterQuality = FilterQuality.high;

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  Future<void> onLoad() async {
    _floor = await images.load('room/floor-oak.png');
    for (final wall in WallStyle.values) {
      _walls[wall] = await images.load(wall.asset);
    }
    for (final style in FurnitureStyle.values) {
      _furniture[style] = await images.load(style.asset);
    }
    for (final style in ArtworkStyle.values) {
      _artworks[style] = await images.load(style.asset);
    }
  }

  double get baseScale => math.min(size.x / 1040, size.y / 1320);
  double get displayScale => baseScale * zoom;
  Offset get origin =>
      Offset(
        (size.x - 1000 * displayScale) / 2,
        (size.y - 1250 * displayScale) / 2,
      ) +
      pan;

  static Offset ground(GridPoint point) => RoomLayout.ground(point);

  void moveView(double nextZoom, Offset focalPoint, Offset delta) {
    final local = (focalPoint - delta - origin) / displayScale;
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

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  void _face(Canvas canvas, List<Offset> points, Color color) {
    final path = _polygon(points);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x88775a3d)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  void _wall(Canvas canvas, ui.Image image, bool left) {
    final end = left ? const Offset(55, 370) : const Offset(945, 370);
    final path = _polygon([
      const Offset(500, 70),
      end,
      end + const Offset(0, 490),
      const Offset(500, 560),
    ]);
    const vertical = 490 / 509;
    final horizontal = 445 / (left ? 487 : 488);
    final shear = (300 - vertical * 307) / (left ? -487 : 488);
    canvas.save();
    canvas.clipPath(path);
    canvas.transform(
      Float64List.fromList([
        horizontal,
        shear,
        0,
        0,
        0,
        vertical,
        0,
        0,
        0,
        0,
        1,
        0,
        500 - horizontal * 560,
        70 - shear * 560 - vertical * 71,
        0,
        1,
      ]),
    );
    canvas.drawImage(image, Offset.zero, _paint);
    canvas.restore();
  }

  void _room(Canvas canvas, ui.Image wall, ui.Image floor) {
    final footprint = _polygon([
      const Offset(500, 560),
      const Offset(945, 860),
      const Offset(500, 1160),
      const Offset(55, 860),
    ]);
    canvas.drawPath(
      footprint.shift(const Offset(0, 24)),
      Paint()
        ..color = const Color(0x3077593e)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
    _face(canvas, [
      const Offset(55, 860),
      const Offset(500, 1160),
      const Offset(500, 1186),
      const Offset(55, 886),
    ], const Color(0xffad7951));
    _face(canvas, [
      const Offset(500, 1160),
      const Offset(945, 860),
      const Offset(945, 886),
      const Offset(500, 1186),
    ], const Color(0xff916240));
    canvas.save();
    canvas.clipPath(footprint);
    canvas.transform(
      Float64List.fromList([
        445 / floor.width,
        300 / floor.width,
        0,
        0,
        -445 / floor.height,
        300 / floor.height,
        0,
        0,
        0,
        0,
        1,
        0,
        500,
        560,
        0,
        1,
      ]),
    );
    canvas.drawImage(
      floor,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    _wall(canvas, wall, true);
    _wall(canvas, wall, false);
    // Wall thickness projects outside the interior, away from the floor.
    _face(canvas, [
      const Offset(500, 46),
      const Offset(37, 358),
      const Offset(55, 370),
      const Offset(500, 70),
    ], const Color(0xffefe1c5));
    _face(canvas, [
      const Offset(500, 46),
      const Offset(963, 358),
      const Offset(945, 370),
      const Offset(500, 70),
    ], const Color(0xfff7ebd4));
    _face(canvas, [
      const Offset(37, 358),
      const Offset(55, 370),
      const Offset(55, 860),
      const Offset(37, 848),
    ], const Color(0xffc9b694));
    _face(canvas, [
      const Offset(945, 370),
      const Offset(963, 358),
      const Offset(963, 848),
      const Offset(945, 860),
    ], const Color(0xffdbc7a4));
    final seam = Paint()
      ..color = const Color(0x70795f45)
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(500, 70), const Offset(500, 560), seam);
    canvas.drawLine(const Offset(55, 860), const Offset(500, 560), seam);
    canvas.drawLine(const Offset(500, 560), const Offset(945, 860), seam);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final wall = _walls[furnishings.wall];
    final floor = _floor;
    if (wall == null || floor == null) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(displayScale);
    _room(canvas, wall, floor);
    if (furnishings.isVisible('painting')) _drawArtwork(canvas);
    if (furnishings.isVisible('window')) _drawFurniture(canvas, 'window');
    final items =
        RoomLayout.defaults.entries
            .where((e) => e.key != 'window' && furnishings.isVisible(e.key))
            .toList()
          ..sort(
            (a, b) => (a.value.x + a.value.y).compareTo(b.value.x + b.value.y),
          );
    // Cat data stays available; furnishing review temporarily omits cat sprites.
    for (final item in items) {
      _drawFurniture(canvas, item.key);
    }
    canvas.restore();
  }

  void _drawFurniture(Canvas canvas, String kind) {
    final style = furnishings.styleFor(kind);
    final image = _furniture[style];
    if (image == null) return;
    final source = furnitureSources[style]![kind]!;
    final geometry = furnitureGeometry[style]![kind]!;
    final scale = furnitureWidths[kind]! / source.width;
    final point = kind == 'window'
        ? ground(RoomLayout.defaults[kind]!) -
              const Offset(0, 245) -
              geometry.bounds(source).center * scale
        : ground(RoomLayout.defaults[kind]!);
    for (final foot in geometry.feet) {
      final contact = geometry.project(foot, scale, point);
      canvas.drawOval(
        Rect.fromCenter(
          center: contact,
          width: kind == 'bed' ? 55 : 18,
          height: kind == 'bed' ? 16 : 7,
        ),
        Paint()
          ..color = const Color(0x48705238)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    geometry.draw(canvas, image, source, scale, point);
  }

  void _drawArtwork(Canvas canvas) {
    final image = _artworks[furnishings.artwork];
    if (image == null) return;
    final center = ground(RoomLayout.paintingSlot) - const Offset(0, 335);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.transform(
      Float64List.fromList([
        1,
        -RoomLayout.slope,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ]),
    );
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(image.width.toDouble(), image.height.toDouble()),
      const Size(168, 190),
    ).destination;
    final picture = Rect.fromCenter(
      center: Offset.zero,
      width: fitted.width,
      height: fitted.height,
    );
    final frame = picture.inflate(11);
    canvas.drawRect(
      frame.shift(const Offset(3, 5)),
      Paint()
        ..color = const Color(0x40705238)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRect(frame, Paint()..color = const Color(0xff775335));
    canvas.drawRect(frame.deflate(3), Paint()..color = const Color(0xffb78a59));
    canvas.drawRect(frame.deflate(7), Paint()..color = const Color(0xfff1e5ce));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      picture,
      _paint,
    );
    canvas.restore();
  }
}
