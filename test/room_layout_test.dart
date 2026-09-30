import 'package:cat_library_demo/room_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial furniture has fixed room slots', () {
    expect(RoomLayout.defaults, {
      'bookshelf': const GridPoint(1, 6),
      'bed': const GridPoint(7, 3),
    });
  });
}
