import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:cat_library_demo/features/room/room_scene.dart';
import 'package:cat_library_demo/features/room/lunar_room.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/room/room_furniture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'three native themes keep registrations, mirrored pixels and valid layout rendering',
    () async {
      final decoded = <String, ui.Image>{};
      Future<ui.Image> load(String path) async {
        if (decoded.containsKey(path)) return decoded[path]!;
        final bytes = await rootBundle.load('assets/images/$path');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        return decoded[path] = image;
      }

      final themes = <String, LunarRoom>{};
      for (final theme in ['lunar', 'wood', 'royal']) {
        themes[theme] = await LunarRoom.load(
          load,
          theme: theme == 'lunar' ? 'lunar-v5' : theme,
        );
      }
      final artwork = {
        for (final a in ArtworkStyle.values) a: await load(a.asset),
      };
      final products = {
        for (final p
            in jsonDecode(
                  await rootBundle.loadString(
                    'assets/data/furniture-products.json',
                  ),
                )
                as List)
          p['sku'] as String: FurnitureProduct.fromJson(
            Map<String, dynamic>.from(p),
          ),
      };
      final slots = PlacementRules(products, const []).slots;
      final scene = RoomScene(fitViewport: true)
        ..onGameResize(Vector2(320, 334))
        ..furnitureFocusArea = const ui.Rect.fromLTRB(32, 80, 288, 185);
      await scene.onLoad();
      for (final product in products.values) {
        final slot = product.placement == 'ground'
            ? null
            : slots.entries.firstWhere((e) => e.value == product.placement).key;
        final item = PlacedItem('bounds-test', gx: 2, gy: 2, slot: slot);
        final bounds = themes['lunar']!.placedSpriteBounds(
          item,
          product,
          themes,
        );
        expect(bounds.width, greaterThan(0), reason: product.sku);
        expect(bounds.height, greaterThan(0), reason: product.sku);
        scene.setFurnitureFocus(item, product, refocus: true);
        final visible = scene.placedViewportBounds(item, product);
        expect(
          scene.furnitureFocusArea!.inflate(1e-8).contains(visible.topLeft),
          isTrue,
          reason: product.sku,
        );
        expect(
          scene.furnitureFocusArea!.inflate(1e-8).contains(visible.bottomRight),
          isTrue,
          reason: product.sku,
        );
        if (product.placement == 'ground') {
          final beforeDrag = scene.origin;
          final moved = item.copy(gx: 6, gy: 6);
          scene.setFurnitureFocus(moved, product);
          expect(
            scene.origin,
            beforeDrag,
            reason: 'drag must not move the view',
          );
          scene.moveView(
            scene.zoom * 1.2,
            const ui.Offset(180, 150),
            const ui.Offset(37, -26),
          );
          final freelyMoved = scene.origin;
          final freelyScaled = scene.displayScale;
          expect(freelyMoved, isNot(beforeDrag));
          scene.setFurnitureFocus(moved.copy(facing: 'y'), product);
          expect(
            scene.origin,
            freelyMoved,
            reason: 'rotation must not snap the view back',
          );
          expect(scene.displayScale, freelyScaled);
          final shifted = themes['lunar']!.placedSpriteBounds(
            item.copy(gx: 3),
            product,
            themes,
          );
          final delta =
              themes['lunar']!.project(1 / 8, 0) -
              themes['lunar']!.project(0, 0);
          expect(
            (shifted.topLeft - bounds.topLeft - delta).distance,
            lessThan(1e-8),
          );
          expect(shifted.width, closeTo(bounds.width, 1e-8));
          expect(shifted.height, closeTo(bounds.height, 1e-8));
        }
      }
      for (final theme in themes.keys) {
        final renderer = themes[theme]!;
        expect(renderer.camera, themes['lunar']!.camera);
        if (theme != 'lunar') {
          final manifest = jsonDecode(
            await File(
              'design/room-themes-2026-10-06/$theme/manifest.json',
            ).readAsString(),
          );
          for (final a in manifest['assets'] as List) {
            if ((a['id'] as String).endsWith('-flat')) continue;
            expect(
              await File('assets/images/room/$theme/${a['png']}').readAsBytes(),
              await File(
                'design/room-themes-2026-10-06/$theme/${a['png']}',
              ).readAsBytes(),
            );
            if (a['category'] == 'furniture') {
              final world = a['worldGroundAnchor'] as List,
                  pixel = a['pixelGroundOrigin'] as List;
              final anchor = renderer.project(world[0], world[1], world[2]);
              expect(
                renderer.layerRect(a['id']).topLeft +
                    ui.Offset(pixel[0].toDouble(), pixel[1].toDouble()),
                anchor,
              );
              expect(
                renderer.layerRect(a['id']).width,
                closeTo(renderer.images[a['id']]!.width, 1e-8),
              );
              expect(
                renderer.layerRect(a['id']).height,
                closeTo(renderer.images[a['id']]!.height, 1e-8),
              );
            }
          }
        }
        for (final kind in ['bookshelf', 'desk', 'chair', 'tree', 'bed']) {
          final x = renderer.images['$kind-x']!,
              y = renderer.images['$kind-y']!;
          expect(
            ui.Size(x.width.toDouble(), x.height.toDouble()),
            ui.Size(y.width.toDouble(), y.height.toDouble()),
          );
          final xb = (await x.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final yb = (await y.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var mismatches = 0;
          for (var row = 0; row < x.height; row++) {
            for (var col = 0; col < x.width; col++) {
              for (var channel = 0; channel < 4; channel++) {
                if (xb[(row * x.width + col) * 4 + channel] !=
                    yb[(row * x.width + x.width - 1 - col) * 4 + channel]) {
                  mismatches++;
                }
              }
            }
          }
          expect(mismatches, 0, reason: '$theme $kind must be a pixel mirror');
        }
        final inventory = <InventoryInstance>[], items = <PlacedItem>[];
        void add(
          String kind, {
          String? slot,
          int gx = 0,
          int gy = 0,
          String facing = 'x',
          String artwork = 'starry',
        }) {
          final id = '$theme-${inventory.length}';
          inventory.add(
            InventoryInstance(id, '$theme-$kind', 'fixture', 'purchase'),
          );
          items.add(
            PlacedItem(
              id,
              slot: slot,
              gx: gx,
              gy: gy,
              facing: facing,
              artwork: artwork,
            ),
          );
        }

        for (final f in renderer.catalog['fixtures']) {
          final anchor = f['orientations']['y']['anchor'];
          add(f['id'], gx: anchor[0], gy: anchor[1], facing: 'y');
        }
        add('wall', slot: 'wall');
        add('floor', slot: 'floor');
        add('rug', slot: 'rug');
        add('window', slot: 'window-left');
        add('window', slot: 'window-right');
        for (final slot in [
          'art-left-back',
          'art-left-front',
          'art-right-back',
          'art-right-front',
        ]) {
          add('frame-portrait', slot: slot, artwork: 'pearl');
        }
        final layout = RoomLayout(items);
        expect(PlacementRules(products, inventory).validate(layout), isEmpty);
        final chair = items.firstWhere(
          (i) =>
              inventory.firstWhere((v) => v.id == i.instanceId).sku ==
              '$theme-chair',
        );
        final cell = products['$theme-chair']!.cells('y').first;
        expect(
          renderer.hitsGround(
            renderer.project(
              (chair.gx + cell.$1 + .5) / 8,
              (chair.gy + cell.$2 + .5) / 8,
              .08,
            ),
            chair,
            products['$theme-chair']!,
          ),
          isTrue,
        );
        expect(
          renderer.hitsGround(
            renderer.project(2, 2),
            chair,
            products['$theme-chair']!,
          ),
          isFalse,
        );
        final pixels = <List<int>>[];
        for (final night in [false, true]) {
          final recorder = ui.PictureRecorder();
          renderer.renderPlaced(
            ui.Canvas(recorder),
            layout,
            products,
            inventory,
            themes,
            night,
            artwork,
          );
          final picture = recorder.endRecording(),
              image = await picture.toImage(1080, 1073);
          picture.dispose();
          if (const bool.fromEnvironment('EXPORT_ROOM_TEST_IMAGES')) {
            await File(
              'docs/evidence/m5-artwork-rendered-$theme-${night ? 'night' : 'day'}.png',
            ).writeAsBytes(
              (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!.buffer.asUint8List(),
            );
          }
          pixels.add(
            (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List().toList(),
          );
          image.dispose();
        }
        var changed = 0;
        for (var i = 0; i < pixels[0].length; i += 4) {
          if (pixels[0][i] != pixels[1][i] ||
              pixels[0][i + 1] != pixels[1][i + 1] ||
              pixels[0][i + 2] != pixels[1][i + 2]) {
            changed++;
            expect((i ~/ 4) % 1080, inInclusiveRange(210, 870));
            expect((i ~/ 4) ~/ 1080, inInclusiveRange(250, 470));
          }
        }
        expect(changed, greaterThan(5000));
      }
      for (final image in decoded.values) {
        image.dispose();
      }
    },
  );
}
