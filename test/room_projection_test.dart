import 'package:cat_library_demo/room_layout.dart';
import 'package:cat_library_demo/features/room/room_furniture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(RoomLayout.defaults['desk']!.y, lessThan(0.1));
    for (final style in FurnitureStyle.values) {
      for (final kind in RoomLayout.defaults.keys) {
        final geometry = furnitureGeometry[style]![kind]!;
        final scale =
            furnitureWidths[kind]! / furnitureSources[style]![kind]!.width;
        final origin = RoomLayout.ground(RoomLayout.defaults[kind]!);
        for (final foot in geometry.feet) {
          expect(geometry.excluded?.contains(foot) ?? false, isFalse);
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
}
