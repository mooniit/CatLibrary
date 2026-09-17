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
    final before = layout.saved['chair'];
    layout.beginEditing();
    layout.move('chair', const GridPoint(2, 7));
    expect(layout.saved['chair'], before);
    expect(layout.draft['chair'], const GridPoint(2, 7));
    layout.commit();
    expect(layout.saved['chair'], const GridPoint(2, 7));
  });

  test('cancel returns all draft objects to the last saved positions', () {
    final layout = RoomLayout();
    layout.beginEditing();
    layout.move('chair', const GridPoint(2, 7));
    layout.cancel();
    expect(layout.draft, layout.saved);
  });

  test('movement is clamped inside the floor and snaps to cells', () {
    final layout = RoomLayout()..beginEditing();
    layout.move('chair', const GridPoint(-20, 50));
    expect(layout.draft['chair'], const GridPoint(1, 8));
    layout.move('chair', const GridPoint(3.2, 5.8));
    expect(layout.draft['chair'], const GridPoint(3, 6));
  });

  test('saved layout roundtrips and invalid data uses defaults', () {
    final layout = RoomLayout()..beginEditing();
    layout.move('table', const GridPoint(2, 6));
    layout.commit();
    expect(RoomLayout.fromJson(layout.toJson()).saved, layout.saved);
    expect(RoomLayout.fromJson('{broken').saved, RoomLayout.defaults);
    expect(
      RoomLayout.fromJson('{"chair":["x",null]}').saved,
      RoomLayout.defaults,
    );
  });
}
