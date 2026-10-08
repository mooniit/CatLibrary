import 'dart:math';

typedef RoomCat = ({String id, String name, String appearance});

enum CatAction { idle, walking, sleeping, petted, resting }

/// Visual-only actions. No wallet, affection or personality values are inferred.
class RoomCatActor {
  RoomCatActor(this.cat)
    : random = Random(
        cat.id.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff),
      );
  RoomCat cat;
  final Random random;
  Point<double> position = const Point(.5, .5);
  Point<double> walkStart = const Point(.5, .5);
  Point<double>? destination;
  CatAction action = CatAction.idle;
  CatAction _resume = CatAction.idle;
  bool visible = false;
  bool faceLeft = false;
  double elapsed = 0;
  double _remaining = 8;
  (int, int) get cell => ((position.x * 8).floor(), (position.y * 8).floor());
  Set<(int, int)> get reservedCells => {
    cell,
    if (destination != null)
      ((walkStart.x * 8).floor(), (walkStart.y * 8).floor()),
    if (destination != null)
      ((destination!.x * 8).floor(), (destination!.y * 8).floor()),
  };

  void _idle() {
    action = CatAction.idle;
    _resume = CatAction.idle;
    elapsed = 0;
    destination = null;
    _remaining = 8 + random.nextDouble() * 8;
  }
}

class CatColony {
  final actors = <String, RoomCatActor>{};
  bool _repairing = false;

  void sync(List<RoomCat> cats) {
    actors.removeWhere((id, _) => !cats.any((cat) => cat.id == id));
    for (final cat in cats) {
      (actors[cat.id] ??= RoomCatActor(cat)).cat = cat;
    }
  }

  bool pet(String id) {
    final a = actors[id];
    if (_repairing || a == null || !a.visible) return false;
    if (a.action == CatAction.petted) return true;
    a._resume = a.destination == null ? CatAction.idle : CatAction.walking;
    a.action = CatAction.petted;
    a.elapsed = 0;
    a._remaining = 2;
    return true;
  }

  void advance(
    double dt, {
    Set<(int, int)> blocked = const {},
    bool repairing = false,
  }) {
    // A suspended app resumes in place, without replaying minutes of animation.
    dt = dt.clamp(0, .1);
    final occupied = <(int, int)>{...blocked};
    final free =
        <(int, int)>[
          for (var y = 0; y < 8; y++)
            for (var x = 0; x < 8; x++) (x, y),
        ]..sort(
          (a, b) => ((a.$1 - 3.5).abs() + (a.$2 - 3.5).abs()).compareTo(
            (b.$1 - 3.5).abs() + (b.$2 - 3.5).abs(),
          ),
        );
    for (final a in actors.values) {
      if (!a.visible || a.reservedCells.any(occupied.contains)) {
        final cell = free.where((c) => !occupied.contains(c)).firstOrNull;
        a.visible = cell != null;
        if (cell == null) continue;
        a.position = Point((cell.$1 + .5) / 8, (cell.$2 + .5) / 8);
        a._idle();
      }
      occupied.addAll(a.reservedCells);
    }
    for (final a in actors.values.where((a) => a.visible)) {
      if (repairing) {
        if (a.action != CatAction.resting) {
          a._resume = a.destination == null
              ? CatAction.idle
              : CatAction.walking;
          a.action = CatAction.resting;
          a.elapsed = 0;
        }
        continue;
      }
      if (_repairing) {
        a.action = a._resume;
        if (a.action == CatAction.idle) a._idle();
      }
      a.elapsed += dt;
      if (a.action == CatAction.walking) {
        final delta = a.destination! - a.position;
        final step = .045 * dt;
        if (delta.magnitude <= step) {
          a.position = a.destination!;
          a._idle();
        } else {
          a.position += delta * (step / delta.magnitude);
        }
        continue;
      }
      a._remaining -= dt;
      if (a._remaining > 0) continue;
      if (a.action == CatAction.petted) {
        a.action = a._resume;
        a.elapsed = 0;
        if (a.action == CatAction.idle) a._idle();
      } else if (a.action == CatAction.sleeping) {
        a._idle();
      } else if (a.random.nextInt(4) == 0) {
        a.action = CatAction.sleeping;
        a.elapsed = 0;
        a._remaining = 20 + a.random.nextDouble() * 20;
      } else {
        final (x, y) = a.cell;
        final neighbours = [(x + 1, y), (x, y + 1), (x - 1, y), (x, y - 1)]
          ..shuffle(a.random);
        final next = neighbours
            .where(
              (c) =>
                  c.$1 >= 0 &&
                  c.$1 < 8 &&
                  c.$2 >= 0 &&
                  c.$2 < 8 &&
                  !occupied.contains(c),
            )
            .firstOrNull;
        if (next == null) {
          a._idle();
          continue;
        }
        a.walkStart = a.position;
        a.destination = Point((next.$1 + .5) / 8, (next.$2 + .5) / 8);
        a.faceLeft =
            (a.destination!.x - a.position.x) <
            (a.destination!.y - a.position.y);
        a.action = CatAction.walking;
        a.elapsed = 0;
        occupied.add(next);
      }
    }
    _repairing = repairing;
  }
}
