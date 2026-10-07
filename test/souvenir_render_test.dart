import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/room/lunar_room.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/room/souvenir_sculpture.dart';
import 'package:cat_library_demo/features/room/furniture_catalog_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'six actual sculpture drawings follow axes, contact, masks and mirrored orientation',
    () async {
      final catalog =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/images/room/lunar-v5/catalog.json',
                ),
              )
              as Map<String, dynamic>;
      final room = LunarRoom(catalog, {});
      final products = [
        for (final p
            in jsonDecode(
                  await rootBundle.loadString(
                    'assets/data/souvenir-products.json',
                  ),
                )
                as List)
          FurnitureProduct.fromJson(Map<String, dynamic>.from(p)),
      ];
      expect(products.length, 6);
      Future<ui.Image> draw(FurnitureProduct product, String facing) async {
        final rec = ui.PictureRecorder();
        SouvenirSculpture.draw(
          ui.Canvas(rec),
          PlacedItem('i', facing: facing),
          product,
          room.project,
        );
        final pic = rec.endRecording(), img = await pic.toImage(1080, 1073);
        pic.dispose();
        return img;
      }

      for (final p in products) {
        await SouvenirSculpture.prepare(p, room.project);
        expect(p.active, false);
        expect(furnitureCategory(p.kind), 'decoration');
        expect(p.cells('x'), [(0, 0)]);
        expect(p.cells('y'), [(0, 0)]);
        final points = [
          for (final f in p.geometry['faces'] as List) ...f['points'] as List,
        ];
        for (final point in points) {
          expect(point[0], inInclusiveRange(.0125, .1125));
          expect(point[1], inInclusiveRange(.0125, .1125));
          expect(point[2], inInclusiveRange(0, p.geometry['x']['h']));
        }
        expect(
          points.any((point) => point[2] == 0),
          true,
          reason: 'contact Z=0',
        );
        final a = await draw(p, 'x'), b = await draw(p, 'y');
        final bytes = (await a.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final mirrored = (await b.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var largestDifference = 0, differing = 0;
        for (var y = 0; y < 1073; y++) {
          for (var x = 0; x < 1080; x++) {
            for (var c = 0; c < 4; c++) {
              final diff =
                  (bytes[(y * 1080 + x) * 4 + c] -
                          mirrored[(y * 1080 + 1079 - x) * 4 + c])
                      .abs();
              if (diff > 0) differing++;
              largestDifference = math.max(largestDifference, diff);
            }
          }
        }
        expect(
          largestDifference,
          0,
          reason:
              '${p.sku} must mirror actual pixels, differing channels=$differing',
        );
        // Measure the actual bottom alpha contour, not a theoretical envelope.
        int bottom(int x) {
          for (var y = 650; y > 480; y--) {
            if (bytes[(y * 1080 + x) * 4 + 3] >= 128) return y;
          }
          throw StateError('missing base');
        }

        for (final range in [(502, 524), (556, 578)]) {
          final slope =
              (bottom(range.$2) - bottom(range.$1)) / (range.$2 - range.$1);
          final angle = math.atan(slope) * 180 / math.pi;
          final expected = range.$1 < 540 ? 26.524611439904 : -26.524611439904;
          expect(
            (angle - expected).abs(),
            lessThan(1),
            reason: '${p.sku} actual base edge follows world axis',
          );
          for (final x in [range.$1, range.$2]) {
            final delta = (x + .5 - 540) / 480;
            final point = range.$1 < 540
                ? room.project(.1125 + delta, .1125)
                : room.project(.1125, .1125 - delta);
            expect(
              (bottom(x) + .5 - point.dy).abs(),
              lessThan(2),
              reason: 'actual edge registration',
            );
          }
        }
        final original = room.placedSpriteBounds(const PlacedItem('i'), p, {}),
            moved = room.placedSpriteBounds(
              const PlacedItem('i', gx: 1),
              p,
              {},
            );
        final delta = moved.topLeft - original.topLeft,
            expectedDelta = room.project(.125, 0) - room.project(0, 0);
        expect(delta.dx, closeTo(expectedDelta.dx, 1e-9));
        expect(delta.dy, closeTo(expectedDelta.dy, 1e-9));
        expect(bytes.take(4), [0, 0, 0, 0], reason: 'transparent canvas');
        if (Platform.environment['EXPORT_ROOM_TEST_IMAGES'] == '1') {
          await File('docs/evidence/m6-${p.sku}-x.png').writeAsBytes(
            (await a.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List(),
          );
        }
        a.dispose();
        b.dispose();
      }
      final inventory = [
        for (var n = 0; n < products.length; n++)
          InventoryInstance('i$n', products[n].sku, null, 'souvenir'),
      ];
      final layout = RoomLayout([
        for (var n = 0; n < products.length; n++)
          PlacedItem(
            'i$n',
            gx: 1 + (n % 3) * 2,
            gy: 1 + (n ~/ 3) * 3,
            facing: n % 2 == 0 ? 'x' : 'y',
          ),
      ]);
      final rules = PlacementRules({
        for (final p in products) p.sku: p,
      }, inventory);
      expect(rules.validate(layout), isEmpty);
      final rec = ui.PictureRecorder();
      room.renderPlaced(
        ui.Canvas(rec),
        layout,
        rules.products,
        inventory,
        {},
        false,
        {},
      );
      final pic = rec.endRecording(), image = await pic.toImage(1080, 1073);
      pic.dispose();
      if (Platform.environment['EXPORT_ROOM_TEST_IMAGES'] == '1') {
        await File('docs/evidence/m6-souvenirs-room.png').writeAsBytes(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
      }
      image.dispose();
    },
  );
}
