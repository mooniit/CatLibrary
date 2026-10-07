import 'dart:ui';

/// Neutral structural shell, not a purchasable or granted inventory instance.
/// All edges are projected from room-standard-v1 by the room's own projector.
class BasicRoomSurfaces {
  static void floor(
    Canvas canvas,
    Offset Function(num, num, [num]) project,
    double thickness,
  ) {
    final outline = Path()
      ..addPolygon([
        project(0, 0),
        project(1, 0),
        project(1, 1),
        project(0, 1),
      ], true);
    final lip = Path()
      ..addPolygon([
        project(0, 1),
        project(1, 1),
        project(1, 0),
        project(1, 0, -thickness),
        project(1, 1, -thickness),
        project(0, 1, -thickness),
      ], true);
    canvas.drawPath(lip, Paint()..color = const Color(0xffc6b49d));
    canvas.drawPath(outline, Paint()..color = const Color(0xffe8dac4));
    canvas.save();
    canvas.clipPath(outline);
    final seam = Paint()
      ..color = const Color(0x50ae9474)
      ..strokeWidth = 1.2;
    for (var i = 1; i < 16; i++) {
      canvas.drawLine(project(i / 16, 0), project(i / 16, 1), seam);
      final y = i.isEven ? .35 : .68;
      canvas.drawLine(project((i - 1) / 16, y), project(i / 16, y), seam);
    }
    canvas.restore();
  }

  static void wall(
    Canvas canvas,
    Offset Function(num, num, [num]) project,
    double height,
    String side,
    double thickness,
  ) {
    Offset point(double s, double z) =>
        side == 'left' ? project(0, s, z) : project(s, 0, z);
    Offset outer(double s, double z) =>
        side == 'left' ? project(-thickness, s, z) : project(s, -thickness, z);
    canvas.drawPath(
      Path()..addPolygon([
        point(0, height),
        point(1, height),
        outer(1, height),
        outer(0, height),
      ], true),
      Paint()..color = const Color(0xfff9faf5),
    );
    canvas.drawPath(
      Path()..addPolygon([
        point(1, 0),
        point(1, height),
        outer(1, height),
        outer(1, 0),
      ], true),
      Paint()..color = const Color(0xffd9deda),
    );
    final outline = Path()
      ..addPolygon([
        point(0, 0),
        point(1, 0),
        point(1, height),
        point(0, height),
      ], true);
    canvas.drawPath(
      outline,
      Paint()
        ..color = side == 'left'
            ? const Color(0xffe9eceb)
            : const Color(0xfff5f5ee),
    );
    canvas.drawLine(
      point(0, .018),
      point(1, .018),
      Paint()
        ..color = const Color(0xffd2d6d2)
        ..strokeWidth = 3,
    );
    canvas.drawPath(
      outline,
      Paint()
        ..color = const Color(0xffcbd2d1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }
}
