import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/room/lunar_room.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/room/room_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unknown repair state restricts care without asserting surface damage',
    () {
      final scene = RoomScene();
      expect(scene.repairing, isTrue);
      expect(scene.confirmedRepairing, isNull);
      scene.repairing = true;
      expect(scene.confirmedRepairing, isTrue);
      scene.repairing = false;
      expect(scene.confirmedRepairing, isFalse);
    },
  );

  test(
    'repair scratches stay on surfaces, behind furnishings, and restore exactly',
    () async {
      final images = <String, ui.Image>{};
      Future<ui.Image> load(String path) async {
        if (images.containsKey(path)) return images[path]!;
        final data = await rootBundle.load('assets/images/$path');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        return images[path] = image;
      }

      final themes = <String, LunarRoom>{};
      for (final theme in ['lunar', 'wood', 'royal']) {
        themes[theme] = await LunarRoom.load(
          load,
          theme: theme == 'lunar' ? 'lunar-v5' : theme,
        );
      }
      addTearDown(() {
        for (final image in images.values) {
          image.dispose();
        }
      });
      final catalog =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/furniture-products.json',
                ),
              )
              as List;
      final room = themes['lunar']!;
      Future<Uint8List> raster(void Function(ui.Canvas) paint) async {
        final recorder = ui.PictureRecorder();
        paint(ui.Canvas(recorder));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1080, 1073);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        return bytes;
      }

      Future<Uint8List> pixels(FurnitureState state, bool worn) => raster(
        (canvas) => room.renderPlaced(
          canvas,
          state.layout,
          state.products,
          state.inventory,
          themes,
          false,
          {},
          worn: worn,
        ),
      );
      bool differs(Uint8List a, Uint8List b, int i) =>
          a[i] != b[i] ||
          a[i + 1] != b[i + 1] ||
          a[i + 2] != b[i + 2] ||
          a[i + 3] != b[i + 3];
      ui.Path plane(List<ui.Offset> points) =>
          ui.Path()..addPolygon(points, true);
      final floor = plane([
        room.project(0, 0),
        room.project(1, 0),
        room.project(1, 1),
        room.project(0, 1),
      ]);
      final height = (room.camera['wallHeight'] as num).toDouble();
      final left = plane([
        room.project(0, 0),
        room.project(0, 1),
        room.project(0, 1, height),
        room.project(0, 0, height),
      ]);
      final right = plane([
        room.project(0, 0),
        room.project(1, 0),
        room.project(1, 0, height),
        room.project(0, 0, height),
      ]);
      for (final theme in ['lunar', 'wood', 'royal', 'empty']) {
        FurnitureState state(bool furnished) => FurnitureState.fromJson({
          'configured': true,
          'products': catalog,
          'version': 3,
          'inventory': theme == 'empty'
              ? []
              : [
                  for (final kind in ['wall', 'floor', 'rug', 'bookshelf'])
                    {'id': kind, 'sku': '$theme-$kind', 'source': 'purchase'},
                ],
          'layout': RoomLayout(
            theme == 'empty'
                ? []
                : [
                    const PlacedItem('wall', slot: 'wall'),
                    const PlacedItem('floor', slot: 'floor'),
                    if (furnished) ...[
                      const PlacedItem('rug', slot: 'rug'),
                      const PlacedItem('bookshelf', gx: 0, gy: 1, facing: 'x'),
                    ],
                  ],
          ).toJson(),
        });
        final bare = state(false);
        final snapshot = jsonEncode(bare.layout.toJson());
        final normal = await pixels(bare, false),
            worn = await pixels(bare, true);
        var floorChanges = 0, leftChanges = 0, rightChanges = 0;
        for (var i = 0; i < normal.length; i += 4) {
          if (!differs(normal, worn, i)) continue;
          final p = ui.Offset(
            ((i ~/ 4) % 1080).toDouble() + .5,
            ((i ~/ 4) ~/ 1080).toDouble() + .5,
          );
          expect(
            floor.contains(p) || left.contains(p) || right.contains(p),
            isTrue,
            reason: '$theme damage escaped a surface at $p',
          );
          if (floor.contains(p)) floorChanges++;
          if (left.contains(p)) leftChanges++;
          if (right.contains(p)) rightChanges++;
        }
        expect(
          floorChanges,
          greaterThan(100),
          reason: '$theme floor has no visible scratches',
        );
        expect(
          leftChanges,
          greaterThan(100),
          reason: '$theme left wall has no visible scratches',
        );
        expect(
          rightChanges,
          greaterThan(100),
          reason: '$theme right wall has no visible scratches',
        );
        expect(await pixels(bare, false), orderedEquals(normal));
        expect(jsonEncode(bare.layout.toJson()), snapshot);
        if (theme == 'empty') continue;
        final furnished = state(true);
        final before = await pixels(furnished, false),
            after = await pixels(furnished, true);
        final mask = await raster((canvas) {
          themes[theme]!.drawLayer(canvas, 'rug');
          themes[theme]!.drawLayer(canvas, 'bookshelf-x');
        });
        var occluded = 0;
        for (var i = 0; i < mask.length; i += 4) {
          if (mask[i + 3] != 255) continue;
          expect(
            differs(before, after, i),
            isFalse,
            reason: '$theme scratch painted over an opaque furnishing',
          );
          if (differs(normal, worn, i)) occluded++;
        }
        expect(
          occluded,
          greaterThan(100),
          reason: '$theme occlusion assertion did not cover any scratch',
        );
        expect(furnished.inventory, hasLength(4));
        expect(furnished.version, 3);
        expect(furnished.rules.validate(furnished.layout), isEmpty);
      }
    },
  );
}
