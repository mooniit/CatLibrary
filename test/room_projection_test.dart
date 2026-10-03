import 'dart:ui' as ui;

import 'package:cat_library_demo/room_layout.dart';
import 'package:cat_library_demo/features/room/room_furniture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('walls, floor and fixed furniture share the same projection', () {
    expect(RoomLayout.ground(const GridPoint(0, 0)), const Offset(500, 560));
    expect(RoomLayout.ground(const GridPoint(10, 0)), const Offset(945, 860));
    expect(RoomLayout.ground(const GridPoint(0, 10)), const Offset(55, 860));
    expect(RoomLayout.ground(const GridPoint(10, 10)), const Offset(500, 1160));
    for (final slot in RoomLayout.defaults.values) {
      final restored = RoomLayout.unproject(RoomLayout.ground(slot));
      expect(restored.x, closeTo(slot.x, 0.00001));
      expect(restored.y, closeTo(slot.y, 0.00001));
    }
    expect(RoomLayout.defaults['bookshelf']!.x, lessThan(0.1));
    expect(RoomLayout.defaults['window'], const GridPoint(5, 0));
    expect(RoomLayout.defaults['chair']!.x, RoomLayout.defaults['desk']!.x);
    expect(RoomLayout.defaults['chair']!.y, RoomLayout.defaults['desk']!.y + 1);
    for (final style in FurnitureStyle.values) {
      for (final kind in RoomLayout.defaults.keys) {
        if (!stylesFor(kind).contains(style) || kind == 'rug') continue;
        final geometry = geometryFor(kind, style);
        final scale = furnitureScale(kind, style);
        final origin = RoomLayout.ground(RoomLayout.defaults[kind]!);
        if (kind == 'bed') {
          final source = sourceFor(kind, style);
          for (final corner in [
            source.topLeft,
            source.topRight,
            source.bottomLeft,
            source.bottomRight,
          ]) {
            final edge = RoomLayout.unproject(
              geometry.project(corner, scale, origin),
            );
            expect(
              edge.x,
              inInclusiveRange(0.2, 9.8),
              reason: '${style.name} basket outer edge X',
            );
            expect(
              edge.y,
              inInclusiveRange(0.2, 9.8),
              reason: '${style.name} basket outer edge Y',
            );
          }
        }
        if (kind == 'desk') {
          final backFoot = RoomLayout.unproject(
            geometry.project(geometry.feet[2], scale, origin),
          );
          expect(
            backFoot.y,
            lessThan(0.1),
            reason: '${style.name} desk against right wall',
          );
        }
        for (final foot in geometry.feet) {
          expect(geometry.excluded.any((rect) => rect.contains(foot)), isFalse);
          final floorPoint = RoomLayout.unproject(
            geometry.project(foot, scale, origin),
          );
          expect(
            floorPoint.x,
            inInclusiveRange(0, 10),
            reason: '${style.name} $kind foot X',
          );
          expect(
            floorPoint.y,
            inInclusiveRange(0, 10),
            reason: '${style.name} $kind foot Y',
          );
        }
        final edge = geometry.project(
          geometry.anchor + Offset(100, 100 * geometry.positiveSlope),
          1,
          Offset.zero,
        );
        expect(edge.dy / edge.dx, closeTo(RoomLayout.slope, 0.00001));
        if (geometry.negativeSlope != null) {
          final other = geometry.project(
            geometry.anchor + Offset(100, 100 * geometry.negativeSlope!),
            1,
            Offset.zero,
          );
          expect(other.dy / other.dx, closeTo(-RoomLayout.slope, 0.00001));
        }
        final upright = geometry.project(
          geometry.anchor - const Offset(0, 100),
          1,
          Offset.zero,
        );
        expect(upright.dx, 0);
      }
    }
  });

  test(
    'original lunar canopy retains its outline and contacts within the floor',
    () {
      const style = FurnitureStyle.lunar;
      final source = sourceFor('bed', style, covered: true);
      final geometry = geometryFor('bed', style, covered: true);
      final scale = furnitureScale('bed', style, covered: true);
      final origin = RoomLayout.ground(RoomLayout.defaults['bed']!);
      for (final point in [
        source.topLeft,
        source.topRight,
        source.bottomLeft,
        source.bottomRight,
        ...geometry.feet,
      ]) {
        final projected = RoomLayout.unproject(
          geometry.project(point, scale, origin),
        );
        expect(projected.x, inInclusiveRange(.2, 9.8));
        expect(projected.y, inInclusiveRange(.2, 9.8));
      }
      expect(
        furnitureAsset('bed', style, covered: true),
        'room/lunar-bed-covered.png',
      );
      expect(RoomLayout.defaults['rug'], const GridPoint(5, 5));
    },
  );

  test(
    'chair crop removes neighboring desk and lamp pixels but retains its front foot',
    () async {
      final bytes = await rootBundle.load(
        'assets/images/room/furniture-sage-v2.png',
      );
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final image = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      final geometry = furnitureGeometry[FurnitureStyle.sage]!['chair']!;
      const origin = Offset(200, 450);
      geometry.draw(
        ui.Canvas(recorder),
        image,
        furnitureSources[FurnitureStyle.sage]!['chair']!,
        1,
        origin,
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(500, 550);
      final pixels = (await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int alphaAt(Offset source) {
        final p = geometry.project(source, 1, origin);
        return pixels.getUint8((p.dy.round() * 500 + p.dx.round()) * 4 + 3);
      }

      expect(
        alphaAt(const Offset(927, 597)),
        0,
        reason: 'neighboring lamp finial',
      );
      expect(
        alphaAt(const Offset(715, 597)),
        0,
        reason: 'neighboring desk book',
      );
      expect(
        alphaAt(const Offset(804, 592)),
        greaterThan(200),
        reason: 'chair front foot',
      );
      rendered.dispose();
      picture.dispose();
      image.dispose();
      codec.dispose();
    },
  );
}
