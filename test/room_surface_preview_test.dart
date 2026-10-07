import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/room/lunar_room.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/shop/shop_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native surface preview replaces the selected layer and empty shell has no window holes',
    () async {
      final images = <String, ui.Image>{};
      Future<ui.Image> load(String path) async {
        if (images.containsKey(path)) return images[path]!;
        final data = await rootBundle.load('assets/images/$path');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final result = (await codec.getNextFrame()).image;
        codec.dispose();
        return images[path] = result;
      }

      final themes = <String, LunarRoom>{};
      for (final t in ['lunar', 'wood', 'royal']) {
        themes[t] = await LunarRoom.load(
          load,
          theme: t == 'lunar' ? 'lunar-v5' : t,
        );
      }
      final catalog =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/furniture-products.json',
                ),
              )
              as List;
      FurnitureState state(List inventory, RoomLayout layout) =>
          FurnitureState.fromJson({
            'configured': true,
            'products': catalog,
            'inventory': inventory,
            'layout': layout.toJson(),
            'version': 0,
          });
      Future<Uint8List> pixels(FurnitureState s) async {
        final recorder = ui.PictureRecorder();
        themes['lunar']!.renderPlaced(
          ui.Canvas(recorder),
          s.layout,
          s.products,
          s.inventory,
          themes,
          false,
          {},
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(1080, 1073);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        return bytes;
      }

      int changes(Uint8List a, Uint8List b) {
        var n = 0;
        for (var i = 0; i < a.length; i += 4) {
          if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
        }
        return n;
      }

      final empty = state([], const RoomLayout([]));
      final neutral = await pixels(empty);
      // The authoritative window centers lie on opaque, unperforated base walls.
      for (final side in ['left', 'right']) {
        final point = themes['lunar']!.wallPoint(side, .5, .50625);
        expect(
          neutral[(point.dy.round() * 1080 + point.dx.round()) * 4 + 3],
          255,
        );
      }
      final base = state(
        [
          {'id': 'wall', 'sku': 'lunar-wall', 'source': 'purchase'},
          {'id': 'floor', 'sku': 'lunar-floor', 'source': 'purchase'},
        ],
        const RoomLayout([
          PlacedItem('wall', slot: 'wall'),
          PlacedItem('floor', slot: 'floor'),
        ]),
      );
      final original = await pixels(base);
      expect(changes(original, neutral), greaterThan(20000));
      for (final theme in ['wood', 'royal']) {
        for (final kind in ['wall', 'floor']) {
          final trial = ShopPreview(base, base.products['$theme-$kind']!);
          expect(
            trial.view.layout.items.where((i) => i.slot == kind),
            hasLength(1),
          );
          expect(trial.view.rules.validate(trial.view.layout), isEmpty);
          expect(
            changes(original, await pixels(trial.view)),
            greaterThan(10000),
            reason: '$theme-$kind must visibly replace lunar',
          );
          expect(
            await pixels(base),
            orderedEquals(original),
            reason: 'preview does not mutate the original',
          );
        }
      }
      for (final image in images.values) {
        image.dispose();
      }
    },
  );
}
