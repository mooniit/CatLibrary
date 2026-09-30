import 'dart:ui';

/// Coordinates on a 10 × 10 floor, shared by walls and furniture.
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
  static const slope = 30 / 44.5;
  static Offset ground(GridPoint point) =>
      Offset(500 + (point.x - point.y) * 44.5, 560 + (point.x + point.y) * 30);

  static GridPoint unproject(Offset point) => GridPoint(
    ((point.dy - 560) / 30 + (point.dx - 500) / 44.5) / 2,
    ((point.dy - 560) / 30 - (point.dx - 500) / 44.5) / 2,
  );

  static const defaults = {
    'window': GridPoint(6.2, 0),
    'chair': GridPoint(7, 6.3),
    'bookshelf': GridPoint(0.08, 5.6),
    'bed': GridPoint(8.5, 4.6),
    'desk': GridPoint(6.2, 0.08),
  };
}
