import 'dart:ui';

typedef RoomProjection = Offset Function(num, num, [num]);

/// The same world bounds and frozen projection are used for all room occupants.
class RoomDepthBody<T> {
  const RoomDepthBody(this.value, this.x, this.y, this.w, this.d, this.h);
  final T value;
  final double x, y, w, d, h;
  List<Offset> hull(RoomProjection p) => [
    p(x, y, h),
    p(x + w, y, h),
    p(x + w, y),
    p(x + w, y + d),
    p(x, y + d),
    p(x, y + d, h),
  ];
}

List<RoomDepthBody<T>> sortRoomBodies<T>(
  List<RoomDepthBody<T>> bodies,
  RoomProjection project,
) {
  final hulls = bodies.map((body) => body.hull(project)).toList();
  final next = List.generate(bodies.length, (_) => <int>[]);
  final indegree = List.filled(bodies.length, 0);
  for (var i = 0; i < bodies.length; i++) {
    for (var j = i + 1; j < bodies.length; j++) {
      final a = bodies[i], b = bodies[j];
      if (!_overlap(hulls[i], hulls[j])) continue;
      final ab = a.x + a.w <= b.x + 1e-8 || a.y + a.d <= b.y + 1e-8;
      final ba = b.x + b.w <= a.x + 1e-8 || b.y + b.d <= a.y + 1e-8;
      if (ab && !ba) {
        next[i].add(j);
        indegree[j]++;
      } else if (ba && !ab) {
        next[j].add(i);
        indegree[i]++;
      }
    }
  }
  final queue = [
    for (var i = 0; i < bodies.length; i++)
      if (indegree[i] == 0) i,
  ];
  final result = <RoomDepthBody<T>>[];
  while (queue.isNotEmpty) {
    final i = queue.removeAt(0);
    result.add(bodies[i]);
    for (final j in next[i]) {
      if (--indegree[j] == 0) queue.add(j);
    }
  }
  if (result.length != bodies.length) throw StateError('房间遮挡存在环，需拆分素材图层');
  return result;
}

bool _overlap(List<Offset> a, List<Offset> b) {
  for (final poly in [a, b]) {
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i], q = poly[(i + 1) % poly.length];
      final axis = Offset(q.dy - p.dy, p.dx - q.dx);
      final aa = a.map((v) => v.dx * axis.dx + v.dy * axis.dy).toList()..sort();
      final bb = b.map((v) => v.dx * axis.dx + v.dy * axis.dy).toList()..sort();
      if (aa.last <= bb.first + 1e-8 || bb.last <= aa.first + 1e-8) {
        return false;
      }
    }
  }
  return true;
}
