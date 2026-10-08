import 'package:cat_library_demo/features/room/room_depth.dart';
import 'package:flutter_test/flutter_test.dart';

Offset project(num x, num y, [num z = 0]) => Offset(
  (540 + 480 * (x - y)).toDouble(),
  537.4716981132076 + 239.57666538848247 * (x + y) - 588.2227833080509 * z,
);

void main() {
  test('a cat behind furniture paints first and one in front paints last', () {
    final chair = RoomDepthBody('chair', .5, .5, .12, .12, .3);
    final back = RoomDepthBody('back-cat', .375, .5, .124, .124, .15);
    final front = RoomDepthBody('front-cat', .625, .5, .124, .124, .15);
    expect(sortRoomBodies([front, chair, back], project).map((b) => b.value), [
      'back-cat',
      'chair',
      'front-cat',
    ]);
  });

  test('Y axis has the same occlusion rule as X, without screen-Y sorting', () {
    final shelf = RoomDepthBody('shelf', .25, .5, .12, .26, .375);
    final cat = RoomDepthBody('cat', .25, .375, .124, .124, .15);
    expect(sortRoomBodies([shelf, cat], project).map((b) => b.value), [
      'cat',
      'shelf',
    ]);
  });

  test('unrelated silhouettes keep stable order', () {
    final a = RoomDepthBody('a', .05, .85, .1, .1, .1);
    final b = RoomDepthBody('b', .85, .05, .1, .1, .1);
    expect(sortRoomBodies([a, b], project).map((b) => b.value), ['a', 'b']);
  });
}
