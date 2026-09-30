/// Ground positions are fixed; future furniture purchases replace the style in a slot.
class GridPoint {
  const GridPoint(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is GridPoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

class RoomLayout {
  static const defaults = {
    'bookshelf': GridPoint(1, 6),
    'bed': GridPoint(7, 3),
  };
}
