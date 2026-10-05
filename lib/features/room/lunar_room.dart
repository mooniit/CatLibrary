import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'room_furniture.dart';

/// Independent approved sprites placed in the frozen room-standard-v1 camera.
class LunarRoom {
  LunarRoom(this.catalog, this.images);
  final Map<String, dynamic> catalog;
  final Map<String, ui.Image> images;
  static const assetRoot = 'room/lunar-v5/';

  static Future<LunarRoom> load(
    Future<ui.Image> Function(String) loadImage,
  ) async {
    final catalog =
        jsonDecode(
              await rootBundle.loadString(
                'assets/images/${assetRoot}catalog.json',
              ),
            )
            as Map<String, dynamic>;
    final images = <String, ui.Image>{};
    final layers = catalog['layers'] as Map<String, dynamic>;
    for (final entry in layers.entries) {
      images[entry.key] = await loadImage('$assetRoot${entry.value['file']}');
    }
    for (final mode in ['day', 'night']) {
      images['sky-$mode'] = await loadImage('${assetRoot}sky-$mode.png');
    }
    return LunarRoom(catalog, images);
  }

  Map<String, dynamic> get standard => catalog['standard'];
  Map<String, dynamic> get camera => standard['camera'];
  ui.Size get size => ui.Size(
    (camera['width'] as num).toDouble(),
    (camera['height'] as num).toDouble(),
  );
  ui.Offset project(num x, num y, [num z = 0]) {
    final o = camera['origin'] as List;
    final bx = camera['bx'] as List;
    final by = camera['by'] as List;
    final bz = camera['bz'] as List;
    return ui.Offset(
      (o[0] + bx[0] * x + by[0] * y + bz[0] * z as num).toDouble(),
      (o[1] + bx[1] * x + by[1] * y + bz[1] * z as num).toDouble(),
    );
  }

  static ui.Rect rect(List values) => ui.Rect.fromLTWH(
    (values[0] as num).toDouble(),
    (values[1] as num).toDouble(),
    (values[2] as num).toDouble(),
    (values[3] as num).toDouble(),
  );
  Map<String, dynamic> layer(String id) => catalog['layers'][id];
  ui.Rect layerRect(String id) => rect(layer(id)['rect']);
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

  void drawLayer(
    ui.Canvas canvas,
    String id, [
    ui.Offset shift = ui.Offset.zero,
  ]) {
    final image = images[id]!;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      layerRect(id).shift(shift),
      _paint,
    );
  }

  bool windowVisible(RoomFurnishings room, String side) =>
      room.isVisible('window') && room.isVisible('window-$side');

  ui.Offset wallPoint(
    String side,
    double s,
    double z, [
    double depth = .0068,
  ]) => side == 'left' ? project(depth, s, z) : project(s, depth, z);

  void _plane(
    ui.Canvas canvas,
    ui.Image image,
    String side,
    double center,
    double z,
    double w,
    double h,
  ) {
    // Both pictures read left-to-right on screen; never reverse their content.
    final start = side == 'left' ? center + w / 2 : center - w / 2;
    final end = side == 'left' ? center - w / 2 : center + w / 2;
    final a = wallPoint(side, start, z + h);
    final b = wallPoint(side, end, z + h);
    final c = wallPoint(side, start, z);
    canvas.save();
    canvas.transform(
      Float64List.fromList([
        (b.dx - a.dx) / image.width,
        (b.dy - a.dy) / image.width,
        0,
        0,
        (c.dx - a.dx) / image.height,
        (c.dy - a.dy) / image.height,
        0,
        0,
        0,
        0,
        1,
        0,
        a.dx,
        a.dy,
        0,
        1,
      ]),
    );
    canvas.drawImage(image, ui.Offset.zero, _paint);
    canvas.restore();
  }

  void _sky(ui.Canvas canvas, Map slot, bool night) {
    final side = slot['wall'] as String;
    final opening = layer('window-$side')['opening'] as Map;
    final s = (slot['s'] as num).toDouble();
    final w = (slot['w'] as num).toDouble();
    final z = (slot['z'] as num).toDouble();
    final low = s - w / 2 + opening['left'];
    final high = s - w / 2 + opening['right'];
    final bottom = z + opening['bottom'];
    final top = z + opening['top'];
    final polygon = ui.Path()
      ..addPolygon([
        wallPoint(side, low, bottom),
        wallPoint(side, high, bottom),
        wallPoint(side, high, top),
        wallPoint(side, low, top),
      ], true);
    final image = images['sky-${night ? 'night' : 'day'}']!;
    final bounds = polygon.getBounds();
    // Two nearby views of one sky. Upright screen crop keeps the moon's phase
    // consistent, instead of reflecting the already projected left window.
    final width = (image.width * .62).clamp(
      1.0,
      image.height * bounds.width / bounds.height * .9,
    );
    final height = width * bounds.height / bounds.width;
    final left = image.width * (side == 'left' ? .03 : .09);
    final source = ui.Rect.fromLTWH(
      left,
      (image.height - height) / 2,
      width,
      height.clamp(1, image.height.toDouble()),
    );
    canvas.save();
    canvas.clipPath(polygon);
    canvas.drawImageRect(image, source, bounds, _paint);
    canvas.restore();
  }

  void _art(
    ui.Canvas canvas,
    Map slot,
    RoomFurnishings room,
    Map<ArtworkStyle, ui.Image> artworks,
  ) {
    final side = slot['wall'] as String;
    final back = (slot['id'] as String).endsWith('back');
    final key = room.frameTemplate == 'auto'
        ? (back ? 'landscape' : 'portrait')
        : room.frameTemplate;
    final template = catalog['frameTemplates'][key] as Map;
    final w = (template['w'] as num).toDouble();
    final h = (template['h'] as num).toDouble();
    final centerZ = (slot['z'] as num).toDouble() + (slot['h'] as num) / 2;
    final centerS = (slot['s'] as num).toDouble();
    final z = centerZ - h / 2;
    final frame = layer('frame-$key-$side');
    final opening = frame['opening'] as Map;
    final innerW = (opening['right'] - opening['left']) as double;
    final innerH = (opening['top'] - opening['bottom']) as double;
    final center = centerS - w / 2 + (opening['left'] + opening['right']) / 2;
    final bottom = z + opening['bottom'];
    final art = room.artwork == ArtworkStyle.starry && !back
        ? ArtworkStyle.pearl
        : room.artwork;
    final image = artworks[art]!;
    final ratio = image.width / image.height;
    final artW = innerW < innerH * ratio ? innerW : innerH * ratio;
    final artH = artW / ratio;
    final backing = ui.Path()
      ..addPolygon([
        wallPoint(side, center - innerW / 2, bottom),
        wallPoint(side, center + innerW / 2, bottom),
        wallPoint(side, center + innerW / 2, bottom + innerH),
        wallPoint(side, center - innerW / 2, bottom + innerH),
      ], true);
    canvas.drawPath(backing, ui.Paint()..color = const ui.Color(0xfff8ead0));
    _plane(
      canvas,
      image,
      side,
      center,
      bottom + (innerH - artH) / 2,
      artW,
      artH,
    );
    final mount = frame['mount'] as List;
    final original = project(mount[0], mount[1], mount[2]);
    final destination = side == 'left'
        ? project(0, centerS, centerZ)
        : project(centerS, 0, centerZ);
    drawLayer(canvas, 'frame-$key-$side', destination - original);
  }

  void render(
    ui.Canvas canvas,
    RoomFurnishings room,
    bool night,
    Map<ArtworkStyle, ui.Image> artworks,
    void Function(String kind, ui.Rect bounds, ui.Offset ground) legacy,
    Map<WallStyle, ui.Image> walls,
    Map<FloorStyle, ui.Image> floors,
  ) {
    drawLayer(canvas, 'floor');
    if (room.floor != FloorStyle.lunar) {
      _floorMaterial(canvas, floors[room.floor]!);
    }
    if (room.isVisible('rug')) {
      if (room.styleFor('rug') == FurnitureStyle.lunar) {
        drawLayer(canvas, 'rug');
      } else {
        legacy('rug', layerRect('rug'), project(.5, .5));
      }
    }
    for (final side in ['left', 'right']) {
      final visible = windowVisible(room, side);
      drawLayer(canvas, 'wall-$side${visible ? '' : '-closed'}');
      if (room.wall != WallStyle.lunar) {
        _wallMaterial(
          canvas,
          walls[room.wall]!,
          side,
          visible,
          flat: room.wall == WallStyle.bauhaus,
        );
      }
      final slot =
          (catalog['slots'] as List).firstWhere(
                (s) => s['id'] == 'window-$side',
              )
              as Map;
      if (visible) {
        _sky(canvas, slot, night);
        if (room.styleFor('window') == FurnitureStyle.lunar) {
          drawLayer(canvas, 'window-$side');
        } else {
          legacy(
            'window',
            layerRect('window-$side'),
            wallPoint(side, .5, (slot['z'] + slot['h'] / 2) as double),
          );
        }
      }
    }
    if (room.isVisible('painting')) {
      for (final slot in (catalog['slots'] as List).where(
        (s) => s['type'] == 'art',
      )) {
        _art(canvas, slot, room, artworks);
      }
    }
    final fixtures =
        (catalog['fixtures'] as List)
            .map((f) {
              final facing = room.facings[f['id']] ?? f['defaultFacing'];
              return f['orientations'][facing] as Map;
            })
            .where((f) => room.isVisible(f['id']))
            .toList()
          ..sort(
            (a, b) => ((a['x'] + a['y'] + a['w'] / 2 + a['d'] / 2) as num)
                .compareTo((b['x'] + b['y'] + b['w'] / 2 + b['d'] / 2) as num),
          );
    for (final f in fixtures) {
      final id = f['id'] as String;
      final sprite = '$id-${f['facing']}';
      if (room.styleFor(id) == FurnitureStyle.lunar &&
          !(id == 'bed' && room.bedCovered)) {
        drawLayer(canvas, sprite);
      } else {
        legacy(id, layerRect(sprite), project(f['x'], f['y']));
      }
    }
  }

  void _floorMaterial(ui.Canvas canvas, ui.Image image) {
    final a = project(0, 0), b = project(1, 0), c = project(0, 1);
    canvas.save();
    canvas.clipPath(ui.Path()..addPolygon([a, b, project(1, 1), c], true));
    canvas.transform(
      Float64List.fromList([
        (b.dx - a.dx) / image.width,
        (b.dy - a.dy) / image.width,
        0,
        0,
        (c.dx - a.dx) / image.height,
        (c.dy - a.dy) / image.height,
        0,
        0,
        0,
        0,
        1,
        0,
        a.dx,
        a.dy,
        0,
        1,
      ]),
    );
    canvas.drawImage(image, ui.Offset.zero, _paint);
    canvas.restore();
  }

  void _wallMaterial(
    ui.Canvas canvas,
    ui.Image image,
    String side,
    bool window, {
    required bool flat,
  }) {
    final h = (camera['wallHeight'] as num).toDouble();
    final path = ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addPolygon([
        wallPoint(side, 0, .032, 0),
        wallPoint(side, 1, .032, 0),
        wallPoint(side, 1, h, 0),
        wallPoint(side, 0, h, 0),
      ], true);
    if (window) {
      path.addPolygon([
        wallPoint(side, .34, .4, 0),
        wallPoint(side, .66, .4, 0),
        wallPoint(side, .66, .6125, 0),
        wallPoint(side, .34, .6125, 0),
      ], true);
    }
    final a = wallPoint(side, 0, h, 0), b = wallPoint(side, 1, h, 0);
    final horizontal = flat
        ? (b.dx - a.dx) / image.width
        : 480 / (side == 'left' ? 487 : 488);
    final vertical = (project(0, 0).dy - a.dy) / (flat ? image.height : 509);
    final shear = flat
        ? (b.dy - a.dy) / image.width
        : ((b.dy - a.dy) - vertical * 307) / (side == 'left' ? -487 : 488);
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
        flat ? a.dx : a.dx - horizontal * 560,
        flat ? a.dy : a.dy - shear * 560 - vertical * 71,
        0,
        1,
      ]),
    );
    canvas.drawImage(image, ui.Offset.zero, _paint);
    canvas.restore();
  }
}
