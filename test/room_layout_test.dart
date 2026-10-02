import 'package:cat_library_demo/room_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial furniture has fixed room slots', () {
    expect(RoomLayout.defaults, {
      'window': const GridPoint(5, 0),
      'chair': const GridPoint(5.4, 2.75),
      'bookshelf': const GridPoint(0.08, 3.2),
      'bed': const GridPoint(9.7, 2.1),
      'desk': const GridPoint(5.4, 1.75),
    });
  });
}
