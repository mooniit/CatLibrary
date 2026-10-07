import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'layout_draft.dart';

/// Selected artwork registered uniformly in the fixed room coordinate system.
/// The second facing is an exact pixel reflection of the first.
class SouvenirSculpture {
  static final _prepared = <String, Future<void>>{};
  static final _sprites = <String, (ui.Rect, ui.Image, ui.Image)>{};
  // Rendering always uses the bundled registration, including while offline
  // inventory still contains catalog metadata cached before this art update.
  static final _registrations = rootBundle
      .loadString('assets/data/souvenir-products.json')
      .then(
        (json) => {
          for (final p in jsonDecode(json) as List)
            p['sku'] as String: p['geometry']['sprite'] as Map,
        },
      );

  static ui.Rect _rect(Map sprite) {
    final values = sprite['rect'] as List;
    return ui.Rect.fromLTWH(
      (values[0] as num).toDouble(),
      (values[1] as num).toDouble(),
      (values[2] as num).toDouble(),
      (values[3] as num).toDouble(),
    );
  }

  static Future<void> prepare(
    FurnitureProduct product,
    ui.Offset Function(num, num, [num]) project,
  ) => _prepared.putIfAbsent(product.sku, () async {
    final sprite = (await _registrations)[product.sku];
    if (sprite == null) throw StateError('未注册的纪念品：${product.sku}');
    Future<ui.Image> load(String path) async {
      final bytes = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }

    final first = await load(sprite['x'] as String);
    try {
      final second = await load(sprite['y'] as String);
      _sprites[product.sku] = (_rect(sprite), first, second);
    } catch (_) {
      first.dispose();
      rethrow;
    }
  });

  static ui.Rect bounds(
    PlacedItem item,
    FurnitureProduct product,
    ui.Offset Function(num, num, [num]) project,
  ) {
    final rect =
        _sprites[product.sku]?.$1 ?? _rect(product.geometry['sprite'] as Map);
    final center = project(.0625, .0625),
        shift = project(item.gx / 8, item.gy / 8) - project(0, 0);
    return (item.facing == 'x'
            ? rect
            : ui.Rect.fromLTWH(
                2 * center.dx - rect.right,
                rect.top,
                rect.width,
                rect.height,
              ))
        .shift(shift);
  }

  static void draw(
    ui.Canvas canvas,
    PlacedItem item,
    FurnitureProduct product,
    ui.Offset Function(num, num, [num]) project,
  ) {
    final sprite = _sprites[product.sku];
    if (sprite == null) throw StateError('纪念品素材尚未注册：${product.sku}');
    final image = item.facing == 'x' ? sprite.$2 : sprite.$3;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bounds(item, product, project),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }
}
