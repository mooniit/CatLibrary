import 'dart:convert';
import 'dart:ui';

/// M0 grid and local draft only; commit does not claim a cloud save.
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
  static const defaults = {'chair': GridPoint(5, 5), 'table': GridPoint(3, 3)};
  Map<String, GridPoint> _saved = Map.of(defaults);
  Map<String, GridPoint> _draft = Map.of(defaults);
  bool editing = false;
  Map<String, GridPoint> get saved => Map.unmodifiable(_saved);
  Map<String, GridPoint> get draft => Map.unmodifiable(_draft);

  static Offset project(GridPoint p) =>
      Offset((p.x - p.y) * 20, (p.x + p.y) * 10);
  static GridPoint unproject(Offset p) =>
      GridPoint(p.dx / 40 + p.dy / 20, p.dy / 20 - p.dx / 40);
  void beginEditing() {
    _draft = Map.of(_saved);
    editing = true;
  }

  void move(String id, GridPoint p) {
    if (!editing || !_draft.containsKey(id) || !p.x.isFinite || !p.y.isFinite) {
      return;
    }
    _draft[id] = GridPoint(
      p.x.round().clamp(1, 8).toDouble(),
      p.y.round().clamp(1, 8).toDouble(),
    );
  }

  void commit() {
    if (editing) _saved = Map.of(_draft);
    editing = false;
  }

  void cancel() {
    _draft = Map.of(_saved);
    editing = false;
  }

  String toJson() => jsonEncode(_saved.map((k, v) => MapEntry(k, [v.x, v.y])));
  RoomLayout();
  factory RoomLayout.fromJson(String json) {
    final result = RoomLayout();
    try {
      final value = jsonDecode(json) as Map<String, dynamic>;
      final parsed = <String, GridPoint>{};
      for (final key in defaults.keys) {
        final pair = value[key] as List<dynamic>;
        if (pair.length != 2) return result;
        final x = (pair[0] as num).toDouble(), y = (pair[1] as num).toDouble();
        if (!x.isFinite ||
            !y.isFinite ||
            x < 1 ||
            x > 8 ||
            y < 1 ||
            y > 8 ||
            x != x.round() ||
            y != y.round()) {
          return result;
        }
        parsed[key] = GridPoint(x, y);
      }
      result._saved = parsed;
      result._draft = Map.of(parsed);
    } on Object {
      /* A corrupt prototype draft must not prevent startup. */
    }
    return result;
  }
}
