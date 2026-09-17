import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../room_layout.dart';

/// Deliberately a wireframe. No artwork or final visual direction is implied.
class RoomScene extends FlameGame {
  RoomScene(this.layout);
  final RoomLayout layout;
  @override
  Color backgroundColor() => const Color(0xfff0f1ed);
  Offset point(GridPoint p) =>
      Offset(size.x / 2, 25) + RoomLayout.project(p) * (size.x / 400);
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final line = Paint()
      ..color = const Color(0xffc1c7c1)
      ..strokeWidth = 1;
    for (var i = 0; i <= 9; i++) {
      canvas.drawLine(
        point(GridPoint(i.toDouble(), 0)),
        point(GridPoint(i.toDouble(), 9)),
        line,
      );
      canvas.drawLine(
        point(GridPoint(0, i.toDouble())),
        point(GridPoint(9, i.toDouble())),
        line,
      );
    }
    final entries =
        (layout.editing ? layout.draft : layout.saved).entries.toList()..sort(
          (a, b) => (a.value.x + a.value.y).compareTo(b.value.x + b.value.y),
        );
    for (final entry in entries) {
      final p = point(entry.value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: p, width: 58, height: 30),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xffd2d7d0),
      );
      label(
        canvas,
        entry.key == 'chair' ? '椅子占位' : '桌子占位',
        p - const Offset(25, 8),
      );
    }
    label(canvas, '黑猫占位', point(const GridPoint(7, 6)));
    label(canvas, '浅色猫占位', point(const GridPoint(4, 8)));
  }

  void label(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xff303a34), fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }
}
