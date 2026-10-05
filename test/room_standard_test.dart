import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cat_library_demo/features/room/lunar_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'packaged camera exactly matches the authoritative portable standard',
    () {
      final catalog =
          jsonDecode(
                File(
                  'assets/images/room/lunar-v5/catalog.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final standard = jsonDecode(
        File(
          'design/room-structure-2026-10-05/room-standard-v1.json',
        ).readAsStringSync(),
      );
      expect(catalog['standard'], standard);
      final room = LunarRoom(catalog, {});
      final xEdge = room.project(1, 0) - room.project(0, 0);
      final yEdge = room.project(0, 1) - room.project(0, 0);
      expect(
        (room.project(.75, .4) - room.project(.25, .4) - xEdge * .5).distance,
        lessThan(1e-8),
      );
      expect(
        (room.project(.3, .8) - room.project(.3, .2) - yEdge * .6).distance,
        lessThan(1e-8),
      );
      expect(xEdge.distance, yEdge.distance);
      expect(
        (room.project(0, 0, standard['camera']['wallHeight']) -
                const ui.Offset(540, 62))
            .distance,
        lessThan(1e-8),
      );
    },
  );

  test(
    'runtime bundle contains only current layers and the reusable paintings',
    () {
      final files = Directory('assets/images/room')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(files, {
        'painting-starry.png',
        'painting-pearl.png',
        'painting-mona.png',
        'painting-scream.png',
        'painting-sunflowers.png',
      });
      expect(File('lib/room_layout.dart').existsSync(), isFalse);
    },
  );
}
