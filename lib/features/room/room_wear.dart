import 'dart:ui';

/// Cosmetic claw marks. Uses the existing room projector and owns no assets,
/// inventory, placement coordinates, or alternative camera calibration.
class RoomWear {
  static void floor(Canvas canvas, Offset Function(num, num, [num]) project) {
    canvas.save();
    canvas.clipPath(
      Path()..addPolygon([
        project(0, 0),
        project(1, 0),
        project(1, 1),
        project(0, 1),
      ], true),
    );
    for (final (x, y) in [(.34, .46), (.78, .63), (.59, .86), (.08, .72)]) {
      _claws(canvas, (s, t) => project(x + s + t * .4, y + t));
    }
    canvas.restore();
  }

  static void wall(
    Canvas canvas,
    Offset Function(num, num, [num]) project,
    double height,
    String side,
  ) {
    Offset point(double s, double z) =>
        side == 'left' ? project(0, s, z) : project(s, 0, z);
    canvas.save();
    canvas.clipPath(
      Path()..addPolygon([
        point(0, 0),
        point(1, 0),
        point(1, height),
        point(0, height),
      ], true),
    );
    // Kept below all fixed window and artwork mounts; furnishings drawn later
    // naturally cover the marks, including the bookshelf near the wall.
    for (final (s, z) in [(.27, .29), (.72, .25), (.88, .15)]) {
      _claws(canvas, (u, v) => point(s + u + v * .12, z - v));
    }
    canvas.restore();
  }

  static void _claws(Canvas canvas, Offset Function(double, double) point) {
    final groove = Paint()
      ..color = const Color(0x996b6258)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;
    final edge = Paint()
      ..color = const Color(0xb3fff5e3)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.25;
    for (var claw = 0; claw < 3; claw++) {
      final s = claw * .013;
      final length = claw == 1 ? .115 : .095;
      Path mark(double offset) {
        final start = point(s + offset, 0);
        final bend = point(s + offset - .012, length * .48);
        final end = point(s + offset + .006, length);
        return Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(bend.dx, bend.dy, end.dx, end.dy);
      }

      canvas.drawPath(mark(0), groove);
      canvas.drawPath(mark(.003), edge);
    }
  }
}
