import 'package:cat_library_demo/room_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial furniture has fixed room slots', () {
    expect(RoomLayout.defaults, {
      'window': const GridPoint(6.2, 0),
      'chair': const GridPoint(7, 6.3),
      'bookshelf': const GridPoint(0.08, 5.6),
      'bed': const GridPoint(8.5, 4.6),
      'desk': const GridPoint(6.2, 0.08),
    });
  });
}
