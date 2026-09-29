import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/room_layout.dart';

void main() {
  test('isometric conversion keeps the same grid cell', () {
    for (final p in [
      const GridPoint(1, 1),
      const GridPoint(7, 3),
      const GridPoint(8, 8),
    ]) {
      final screen = RoomLayout.project(p);
      expect(RoomLayout.unproject(screen), p);
    }
  });

  test('moving a draft does not modify saved furniture until save', () {
    final layout = RoomLayout();
    final before = layout.saved['bookshelf'];
    layout.beginEditing();
    layout.move('bookshelf', const GridPoint(2, 7));
    expect(layout.saved['bookshelf'], before);
    expect(layout.draft['bookshelf'], const GridPoint(2, 7));
    layout.commit();
    expect(layout.saved['bookshelf'], const GridPoint(2, 7));
  });

  test('cancel returns all draft objects to the last saved positions', () {
    final layout = RoomLayout();
    layout.beginEditing();
    layout.move('bookshelf', const GridPoint(2, 7));
    layout.cancel();
    expect(layout.draft, layout.saved);
  });

  test('movement is clamped inside the floor and snaps to cells', () {
    final layout = RoomLayout()..beginEditing();
    layout.move('bookshelf', const GridPoint(-20, 50));
    expect(layout.draft['bookshelf'], const GridPoint(1, 8));
    layout.move('bookshelf', const GridPoint(3.2, 5.8));
    expect(layout.draft['bookshelf'], const GridPoint(3, 6));
  });

  test('saved layout roundtrips and invalid data uses defaults', () {
    final layout = RoomLayout()..beginEditing();
    layout.move('bed', const GridPoint(2, 6));
    layout.commit();
    expect(RoomLayout.fromJson(layout.toJson()).saved, layout.saved);
    expect(RoomLayout.fromJson('{broken').saved, RoomLayout.defaults);
    expect(
      RoomLayout.fromJson('{"bookshelf":["x",null]}').saved,
      RoomLayout.defaults,
    );
  });
}
