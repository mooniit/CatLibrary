import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/room/cat_behavior.dart';

void main() {
  const cats = [
    (id: 'a', name: '花花', appearance: 'black_short'),
    (id: 'b', name: '团团', appearance: 'black_short'),
    (id: 'c', name: '雪雪', appearance: 'light_long'),
    (id: 'd', name: '绒绒', appearance: 'light_long'),
  ];

  test(
    'four cats keep independent identities and positions across a refresh',
    () {
      final room = CatColony()..sync(cats);
      room.advance(1);
      final first = room.actors['a']!;
      final position = first.position;
      room.sync(cats.reversed.toList());
      expect(identical(room.actors['a'], first), isTrue);
      expect(first.position, position);
      expect(room.actors.values.map((a) => a.position).toSet(), hasLength(4));
      room.sync(
        cats.sublist(1),
      ); // Travelling cat is absent from the room snapshot.
      expect(room.actors.containsKey('a'), isFalse);
    },
  );

  test(
    'walking follows cardinal steps and never enters furniture or other cats',
    () {
      final blocked = {for (var y = 0; y < 8; y++) (3, y)};
      final room = CatColony()..sync(cats);
      var walked = false;
      for (var frame = 0; frame < 3600; frame++) {
        room.advance(.1, blocked: blocked);
        final reservations = <(int, int)>{};
        for (final a in room.actors.values.where((a) => a.visible)) {
          expect(a.position.x, inInclusiveRange(.5 / 8, 7.5 / 8));
          expect(a.position.y, inInclusiveRange(.5 / 8, 7.5 / 8));
          for (final cell in a.reservedCells) {
            expect(blocked.contains(cell), isFalse);
            expect(reservations.add(cell), isTrue);
          }
          if (a.action == CatAction.walking) {
            walked = true;
            final end = a.destination!;
            expect(end.x == a.walkStart.x || end.y == a.walkStart.y, isTrue);
          }
        }
      }
      expect(walked, isTrue);
    },
  );

  test(
    'new furniture relocates a cat; fully occupied room hides it safely',
    () {
      final room = CatColony()..sync([cats.first]);
      room.advance(0);
      final a = room.actors['a']!;
      final old = a.position;
      room.advance(0, blocked: a.reservedCells);
      expect(a.position, isNot(old));
      room.advance(
        0,
        blocked: {
          for (var x = 0; x < 8; x++)
            for (var y = 0; y < 8; y++) (x, y),
        },
      );
      expect(a.visible, isFalse);
      expect(room.pet('a'), isFalse);
      room.advance(0);
      expect(a.visible, isTrue);
    },
  );

  test(
    'repair freezes walking and refuses petting until a confirmed release',
    () {
      final room = CatColony()..sync([cats.first]);
      while (room.actors['a']!.action != CatAction.walking) {
        room.advance(.1);
      }
      final a = room.actors['a']!;
      room.advance(.1, repairing: true);
      final position = a.position;
      expect(a.action, CatAction.resting);
      expect(room.pet('a'), isFalse);
      room.advance(30, repairing: true);
      expect(a.position, position);
      room.advance(.1, repairing: false);
      expect(room.pet('a'), isTrue);
    },
  );

  test(
    'sleep and pet feedback are temporary visual states without rewards',
    () {
      final room = CatColony()..sync([cats.first]);
      final a = room.actors['a']!;
      for (var i = 0; i < 3600 && a.action != CatAction.sleeping; i++) {
        room.advance(.1);
      }
      expect(a.action, CatAction.sleeping);
      expect(room.pet('a'), isTrue);
      expect(a.action, CatAction.petted);
      for (var i = 0; i < 25; i++) {
        room.advance(.1);
      }
      expect(a.action, CatAction.idle);
      expect(room.pet('missing'), isFalse);
    },
  );

  test('petting during a walk pauses then resumes the same reserved path', () {
    final room = CatColony()..sync([cats.first]);
    final a = room.actors['a']!;
    while (a.action != CatAction.walking) {
      room.advance(.1);
    }
    final destination = a.destination, position = a.position;
    expect(room.pet('a'), isTrue);
    for (var i = 0; i < 10; i++) {
      room.advance(.1);
    }
    expect(a.position, position);
    expect(a.destination, destination);
    for (var i = 0; i < 15; i++) {
      room.advance(.1);
    }
    expect(a.action, CatAction.walking);
    expect(a.destination, destination);
    expect(a.position, isNot(position));
  });

  test(
    'furniture moving during repair cannot resume a discarded walking path',
    () {
      final room = CatColony()..sync([cats.first]);
      final a = room.actors['a']!;
      while (a.action != CatAction.walking) {
        room.advance(.1);
      }
      room.advance(.1, repairing: true);
      room.advance(.1, repairing: true, blocked: a.reservedCells);
      room.advance(.1, repairing: false);
      expect(a.action, CatAction.idle);
      expect(a.destination, isNull);
    },
  );

  test('resuming after a long frame does not teleport across the room', () {
    final room = CatColony()..sync([cats.first]);
    while (room.actors['a']!.action != CatAction.walking) {
      room.advance(.1);
    }
    final a = room.actors['a']!, before = room.actors['a']!.position;
    room.advance(10000);
    expect(a.position.distanceTo(before), lessThanOrEqualTo(.006));
    expect(a.position, isA<Point<double>>());
  });
}
