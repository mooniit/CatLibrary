import 'dart:math' as math;
import 'dart:ui' as ui;
import 'layout_draft.dart';

/// Registered numeric sculptures; the second facing reflects the first drawing.
class SouvenirSculpture {
  static final _prepared = <String, Future<void>>{};
  static final _sprites = <String, (ui.Rect, ui.Image, ui.Image)>{};
  static Future<void> prepare(
    FurnitureProduct product,
    ui.Offset Function(num, num, [num]) project,
  ) => _prepared.putIfAbsent(product.sku, () async {
    final bounds = SouvenirSculpture.bounds(
      const PlacedItem('source'),
      product,
      project,
    );
    final rect = ui.Rect.fromLTRB(
      bounds.left.floorToDouble(),
      bounds.top.floorToDouble(),
      bounds.right.ceilToDouble(),
      bounds.bottom.ceilToDouble(),
    );
    final firstRecorder = ui.PictureRecorder(),
        firstCanvas = ui.Canvas(firstRecorder);
    firstCanvas.translate(-rect.left, -rect.top);
    _drawModel(firstCanvas, product, project);
    final firstPicture = firstRecorder.endRecording(),
        first = await firstPicture.toImage(
          rect.width.toInt(),
          rect.height.toInt(),
        );
    firstPicture.dispose();
    final mirrorRecorder = ui.PictureRecorder(),
        mirrorCanvas = ui.Canvas(mirrorRecorder);
    mirrorCanvas.translate(rect.width, 0);
    mirrorCanvas.scale(-1, 1);
    mirrorCanvas.drawImage(
      first,
      ui.Offset.zero,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false,
    );
    final mirrorPicture = mirrorRecorder.endRecording(),
        mirror = await mirrorPicture.toImage(first.width, first.height);
    mirrorPicture.dispose();
    _sprites[product.sku] = (rect, first, mirror);
  });
  static List<ui.Offset> _points(
    Map face,
    ui.Offset Function(num, num, [num]) project,
  ) => [for (final p in face['points'] as List) project(p[0], p[1], p[2])];
  static ui.Rect bounds(
    PlacedItem item,
    FurnitureProduct product,
    ui.Offset Function(num, num, [num]) project,
  ) {
    final center = project(.0625, .0625),
        shift = project(item.gx / 8, item.gy / 8) - project(0, 0);
    final points =
        [
              for (final face in product.geometry['faces'] as List)
                ..._points(face, project),
            ]
            .map(
              (p) =>
                  (item.facing == 'y'
                      ? ui.Offset(2 * center.dx - p.dx, p.dy)
                      : p) +
                  shift,
            )
            .toList();
    return ui.Rect.fromLTRB(
      points.map((p) => p.dx).reduce(math.min),
      points.map((p) => p.dy).reduce(math.min),
      points.map((p) => p.dx).reduce(math.max),
      points.map((p) => p.dy).reduce(math.max),
    ).inflate(.5);
  }

  static void draw(
    ui.Canvas canvas,
    PlacedItem item,
    FurnitureProduct product,
    ui.Offset Function(num, num, [num]) project,
  ) {
    final sprite = _sprites[product.sku];
    if (sprite == null) throw StateError('纪念品素材尚未注册：${product.sku}');
    final shift = project(item.gx / 8, item.gy / 8) - project(0, 0),
        center = project(.0625, .0625);
    final origin = item.facing == 'x'
        ? sprite.$1.topLeft
        : ui.Offset(2 * center.dx - sprite.$1.right, sprite.$1.top);
    canvas.drawImage(
      item.facing == 'x' ? sprite.$2 : sprite.$3,
      origin + shift,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }

  static void _drawModel(
    ui.Canvas canvas,
    FurnitureProduct product,
    ui.Offset Function(num, num, [num]) project,
  ) {
    for (final face in product.geometry['faces'] as List) {
      final path = ui.Path()..addPolygon(_points(face, project), true);
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = ui.Color(
            int.parse('ff${(face['color'] as String).substring(1)}', radix: 16),
          ),
      );
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = const ui.Color(0xff526773)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = .45
          ..strokeJoin = ui.StrokeJoin.round,
      );
    }
  }
}
