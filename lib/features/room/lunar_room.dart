import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'room_furniture.dart';
import 'layout_draft.dart';
import 'basic_room_surfaces.dart';
import 'room_wear.dart';
import 'souvenir_sculpture.dart';
import 'room_depth.dart';

/// Independent approved sprites placed in the frozen room-standard-v1 camera.
class LunarRoom {
  LunarRoom(this.catalog, this.images);
  final Map<String, dynamic> catalog;
  final Map<String, ui.Image> images;
  static const assetRoot = 'room/lunar-v5/';

  static Future<LunarRoom> load(
    Future<ui.Image> Function(String) loadImage, {
    String theme = 'lunar-v5',
  }) async {
    final root = 'room/$theme/';
    final catalog =
        jsonDecode(
              await rootBundle.loadString('assets/images/${root}catalog.json'),
            )
            as Map<String, dynamic>;
    final images = <String, ui.Image>{};
    final layers = catalog['layers'] as Map<String, dynamic>;
    for (final entry in layers.entries) {
      images[entry.key] = await loadImage('$root${entry.value['file']}');
    }
    if (theme == 'lunar-v5') {
      for (final mode in ['day', 'night']) {
        images['sky-$mode'] = await loadImage('${root}sky-$mode.png');
      }
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
    Map<ArtworkStyle, ui.Image> artworks, {
    bool pairedDefaults = true,
  }) {
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
    final art = pairedDefaults && room.artwork == ArtworkStyle.starry && !back
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

  /// Placement translates registered sprites along world axes, never stretches them.
  void renderPlaced(
    ui.Canvas canvas,
    RoomLayout layout,
    Map<String, FurnitureProduct> products,
    List<InventoryInstance> inventory,
    Map<String, LunarRoom> themes,
    bool night,
    Map<ArtworkStyle, ui.Image> artworks, {
    String? selected,
    bool worn = false,
  }) {
    final byId = {for (final i in inventory) i.id: i};
    FurnitureProduct? product(PlacedItem i) =>
        products[byId[i.instanceId]?.sku];
    PlacedItem? mounted(String slot) =>
        layout.items.where((i) => i.slot == slot).firstOrNull;
    LunarRoom skin(PlacedItem? i) =>
        i == null ? this : themes[product(i)?.theme] ?? this;
    if (mounted('floor') == null) {
      BasicRoomSurfaces.floor(
        canvas,
        project,
        (standard['floorThickness'] as num).toDouble(),
      );
    } else {
      skin(mounted('floor')).drawLayer(canvas, 'floor');
    }
    if (worn) RoomWear.floor(canvas, project);
    final rug = mounted('rug');
    if (rug != null) skin(rug).drawLayer(canvas, 'rug');
    final walls = skin(mounted('wall'));
    for (final side in ['left', 'right']) {
      final window = mounted('window-$side');
      if (mounted('wall') == null) {
        BasicRoomSurfaces.wall(
          canvas,
          project,
          (camera['wallHeight'] as num).toDouble(),
          side,
          (standard['wallThickness'] as num).toDouble(),
        );
      } else {
        walls.drawLayer(canvas, 'wall-$side${window == null ? '-closed' : ''}');
      }
      if (worn) {
        RoomWear.wall(
          canvas,
          project,
          (camera['wallHeight'] as num).toDouble(),
          side,
        );
      }
      if (window != null) {
        final renderer = skin(window);
        final slot =
            (catalog['slots'] as List).firstWhere(
                  (s) => s['id'] == 'window-$side',
                )
                as Map;
        if (renderer.images.containsKey('sky-day')) {
          renderer._sky(canvas, slot, night);
        } else {
          renderer.drawLayer(canvas, 'view-$side-${night ? 'night' : 'day'}');
        }
        renderer.drawLayer(canvas, 'window-$side');
      }
    }
    for (final slot in (catalog['slots'] as List).where(
      (s) => s['type'] == 'art',
    )) {
      final item = mounted(slot['id']);
      if (item == null) continue;
      final p = product(item);
      if (p == null) continue;
      skin(item)._art(
        canvas,
        slot,
        RoomFurnishings(
          frameTemplate: p.geometry['template'],
          artwork: ArtworkStyle.values.byName(p.artwork ?? item.artwork),
        ),
        artworks,
        pairedDefaults: false,
      );
    }
    final floor = layout.items
        .where((i) => product(i)?.placement == 'ground')
        .toList();
    for (final item in sortPlaced(floor, products, inventory)) {
      final p = product(item)!;
      if (p.kind == 'souvenir') {
        if (selected != null && selected != item.instanceId) {
          canvas.saveLayer(
            null,
            ui.Paint()..color = const ui.Color(0x70ffffff),
          );
        }
        SouvenirSculpture.draw(canvas, item, p, project);
        if (selected != null && selected != item.instanceId) canvas.restore();
        continue;
      }
      final renderer = skin(item);
      final f = (renderer.catalog['fixtures'] as List).firstWhere(
        (f) => f['id'] == p.kind,
      );
      final anchor = f['orientations'][item.facing]['anchor'] as List;
      final shift =
          project((item.gx - anchor[0]) / 8, (item.gy - anchor[1]) / 8) -
          project(0, 0);
      if (selected != null && selected != item.instanceId) {
        canvas.saveLayer(null, ui.Paint()..color = const ui.Color(0x70ffffff));
        renderer.drawLayer(canvas, '${p.kind}-${item.facing}', shift);
        canvas.restore();
      } else {
        renderer.drawLayer(canvas, '${p.kind}-${item.facing}', shift);
      }
    }
  }

  /// UI controls use the same registered rectangles and world translation as drawing.
  ui.Rect placedSpriteBounds(
    PlacedItem item,
    FurnitureProduct p,
    Map<String, LunarRoom> themes,
  ) {
    final renderer = themes[p.theme] ?? this;
    if (p.kind == 'souvenir') return SouvenirSculpture.bounds(item, p, project);
    if (p.placement == 'ground') {
      final fixture = (renderer.catalog['fixtures'] as List).firstWhere(
        (f) => f['id'] == p.kind,
      );
      final anchor = fixture['orientations'][item.facing]['anchor'] as List;
      final shift =
          project((item.gx - anchor[0]) / 8, (item.gy - anchor[1]) / 8) -
          project(0, 0);
      return renderer.layerRect('${p.kind}-${item.facing}').shift(shift);
    }
    if (p.placement == 'window') {
      return renderer.layerRect(
        'window-${item.slot == 'window-right' ? 'right' : 'left'}',
      );
    }
    if (p.placement == 'art') {
      final slot =
          (catalog['slots'] as List).firstWhere((s) => s['id'] == item.slot)
              as Map;
      final side = slot['wall'] as String;
      final frame = renderer.layer('frame-${p.geometry['template']}-$side');
      final mount = frame['mount'] as List;
      final s = slot['s'] as num,
          z = (slot['z'] as num) + (slot['h'] as num) / 2;
      final destination = side == 'left' ? project(0, s, z) : project(s, 0, z);
      return rect(
        frame['rect'],
      ).shift(destination - project(mount[0], mount[1], mount[2]));
    }
    if (p.placement == 'wall') {
      return renderer
          .layerRect('wall-left-closed')
          .expandToInclude(renderer.layerRect('wall-right-closed'));
    }
    return renderer.layerRect(p.placement);
  }

  void renderGhost(
    ui.Canvas canvas,
    PlacedItem item,
    FurnitureProduct p,
    Map<String, LunarRoom> themes,
    bool night,
    Map<ArtworkStyle, ui.Image> artworks, {
    double opacity = .5,
  }) {
    final renderer = themes[p.theme] ?? this;
    canvas.saveLayer(
      null,
      ui.Paint()..color = const ui.Color(0xffffffff).withValues(alpha: opacity),
    );
    if (p.kind == 'souvenir') {
      SouvenirSculpture.draw(canvas, item, p, project);
    } else if (p.placement == 'ground') {
      final f = (renderer.catalog['fixtures'] as List).firstWhere(
        (f) => f['id'] == p.kind,
      );
      final anchor = f['orientations'][item.facing]['anchor'] as List;
      final shift =
          project((item.gx - anchor[0]) / 8, (item.gy - anchor[1]) / 8) -
          project(0, 0);
      renderer.drawLayer(canvas, '${p.kind}-${item.facing}', shift);
    } else if (p.placement == 'window') {
      final side = item.slot == 'window-right' ? 'right' : 'left';
      final slot =
          (catalog['slots'] as List).firstWhere((s) => s['id'] == item.slot)
              as Map;
      if (renderer.images.containsKey('sky-day')) {
        renderer._sky(canvas, slot, night);
      } else {
        renderer.drawLayer(canvas, 'view-$side-${night ? 'night' : 'day'}');
      }
      renderer.drawLayer(canvas, 'window-$side');
    } else if (p.placement == 'art') {
      final slot =
          (catalog['slots'] as List).firstWhere((s) => s['id'] == item.slot)
              as Map;
      renderer._art(
        canvas,
        slot,
        RoomFurnishings(
          frameTemplate: p.geometry['template'],
          artwork: ArtworkStyle.values.byName(p.artwork ?? item.artwork),
        ),
        artworks,
        pairedDefaults: false,
      );
    } else if (p.placement == 'wall') {
      for (final side in ['left', 'right']) {
        renderer.drawLayer(canvas, 'wall-$side-closed');
      }
    } else {
      renderer.drawLayer(canvas, p.kind);
    }
    canvas.restore();
  }

  List<PlacedItem> sortPlaced(
    List<PlacedItem> items,
    Map<String, FurnitureProduct> products,
    List<InventoryInstance> inventory,
  ) {
    final byId = {for (final i in inventory) i.id: i};
    final boxes = [
      for (final i in items) _PlacedBox(i, products[byId[i.instanceId]!.sku]!),
    ];
    return sortRoomBodies<PlacedItem>(
      boxes,
      project,
    ).map((b) => b.value).toList();
  }

  bool hitsGround(ui.Offset point, PlacedItem item, FurnitureProduct product) =>
      (ui.Path()..addPolygon(_PlacedBox(item, product).hull(project), true))
          .contains(point);

  void render(
    ui.Canvas canvas,
    RoomFurnishings room,
    bool night,
    Map<ArtworkStyle, ui.Image> artworks, {
    bool worn = false,
  }) {
    drawLayer(canvas, 'floor');
    if (worn) RoomWear.floor(canvas, project);
    if (room.isVisible('rug')) drawLayer(canvas, 'rug');
    for (final side in ['left', 'right']) {
      final visible = windowVisible(room, side);
      drawLayer(canvas, 'wall-$side${visible ? '' : '-closed'}');
      if (worn) {
        RoomWear.wall(
          canvas,
          project,
          (camera['wallHeight'] as num).toDouble(),
          side,
        );
      }
      final slot =
          (catalog['slots'] as List).firstWhere(
                (s) => s['id'] == 'window-$side',
              )
              as Map;
      if (visible) {
        _sky(canvas, slot, night);
        drawLayer(canvas, 'window-$side');
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
            .map((f) => f['orientations'][room.facingFor(f['id'])] as Map)
            .where((f) => room.isVisible(f['id']))
            .toList()
          ..sort(
            (a, b) => ((a['x'] + a['y'] + a['w'] / 2 + a['d'] / 2) as num)
                .compareTo((b['x'] + b['y'] + b['w'] / 2 + b['d'] / 2) as num),
          );
    for (final f in fixtures) {
      drawLayer(canvas, "${f['id']}-${f['facing']}");
    }
  }
}

class _PlacedBox extends RoomDepthBody<PlacedItem> {
  factory _PlacedBox(PlacedItem item, FurnitureProduct product) {
    final g = product.geometry[item.facing], cells = product.cells(item.facing);
    final maxX = cells.map((c) => c.$1).reduce((a, b) => a > b ? a : b),
        maxY = cells.map((c) => c.$2).reduce((a, b) => a > b ? a : b);
    final w = (g['w'] as num).toDouble(),
        d = (g['d'] as num).toDouble(),
        h = (g['h'] as num).toDouble();
    final x = (item.gx + (maxX + 1) / 2) / 8 - w / 2;
    final y = (item.gy + (maxY + 1) / 2) / 8 - d / 2;
    return _PlacedBox._(item, x, y, w, d, h);
  }
  const _PlacedBox._(super.value, super.x, super.y, super.w, super.d, super.h);
}
