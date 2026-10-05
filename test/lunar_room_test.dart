import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cat_library_demo/features/room/lunar_room.dart';
import 'package:cat_library_demo/features/room/room_furniture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cat_library_demo/features/room/furniture_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lunar renderer uses the exact portable standard and all 32 valid facings',
    () async {
      final catalog =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/images/room/lunar-v5/catalog.json',
                ),
              )
              as Map<String, dynamic>;
      final scene = LunarRoom(catalog, {});
      expect(scene.standard['id'], 'room-standard-v1');
      expect(scene.standard['gridSize'], 8);
      expect(scene.size, const ui.Size(1080, 1073));
      expect(scene.project(0, 0), const ui.Offset(540, 537.4716981132076));
      expect(
        scene.project(0, 0, scene.camera['wallHeight']).dy,
        closeTo(62, 1e-8),
      );
      expect(scene.project(1, 1).dy, closeTo(1016.6250288901726, 1e-8));
      final fixtures = catalog['fixtures'] as List;
      for (var combination = 0; combination < 32; combination++) {
        final occupied = <String>{};
        for (var i = 0; i < fixtures.length; i++) {
          final f =
              fixtures[i]['orientations'][(combination & (1 << i)) == 0
                      ? 'x'
                      : 'y']
                  as Map;
          for (final cell in f['cells'] as List) {
            expect(cell[0], inInclusiveRange(0, 7));
            expect(cell[1], inInclusiveRange(0, 7));
            expect(occupied.add(cell.toString()), isTrue);
          }
          expect(f['x'], greaterThanOrEqualTo(0));
          expect(f['y'], greaterThanOrEqualTo(0));
          expect(f['x'] + f['w'], lessThanOrEqualTo(1));
          expect(f['y'] + f['d'], lessThanOrEqualTo(1));
          final layer = scene.layer('${f['id']}-${f['facing']}');
          expect(
            (await rootBundle.load(
              'assets/images/room/lunar-v5/${layer['file']}',
            )).lengthInBytes,
            greaterThan(100),
          );
        }
      }
    },
  );
  test(
    'native lunar choices survive saves and do not leak between owners',
    () async {
      SharedPreferences.setMockInitialValues({});
      final lunar = const RoomFurnishings()
          .withSet(FurnitureStyle.lunar)
          .withFacing('desk', 'x')
          .withFrameTemplate('square')
          .withVisibility('window-left', false);
      await lunar.save('owner-a');
      final restored = await RoomFurnishings.load('owner-a');
      expect(restored.facings['desk'], 'x');
      expect(restored.frameTemplate, 'square');
      expect(restored.isVisible('window-left'), isFalse);
      expect(restored.isVisible('window-right'), isTrue);
      expect(restored.wall, WallStyle.lunar);
      final other = await RoomFurnishings.load('owner-b');
      expect(other.wall, WallStyle.lunar);
      expect(other.facings, isEmpty);
      expect(() => lunar.withFacing('desk', 'z'), throwsArgumentError);
      expect(() => lunar.withFrameTemplate('round'), throwsArgumentError);
      expect(
        restored.withStyle('desk', FurnitureStyle.lunar).frameTemplate,
        'square',
      );
    },
  );
  test(
    'native layers render all three templates and day/night changes only the sky',
    () async {
      final decoded = <String, ui.Image>{};
      Future<ui.Image> load(String path) async {
        if (decoded.containsKey(path)) return decoded[path]!;
        final bytes = await rootBundle.load('assets/images/$path');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        return decoded[path] = frame.image;
      }

      final lunar = await LunarRoom.load(load);
      final artwork = <ArtworkStyle, ui.Image>{};
      for (final style in ArtworkStyle.values) {
        artwork[style] = await load(style.asset);
      }
      final room = const RoomFurnishings().withSet(FurnitureStyle.lunar);
      final renders = <String, List<int>>{};
      for (final template in ['landscape', 'portrait', 'square']) {
        for (final night in [false, true]) {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          lunar.render(
            canvas,
            room.withFrameTemplate(template),
            night,
            artwork,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(1080, 1073);
          picture.dispose();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          renders['$template-$night'] = bytes.toList();
          image.dispose();
        }
      }
      final day = renders['landscape-false']!,
          night = renders['landscape-true']!;
      var changed = 0;
      for (var i = 0; i < day.length; i += 4) {
        if (day[i] != night[i] ||
            day[i + 1] != night[i + 1] ||
            day[i + 2] != night[i + 2]) {
          changed++;
          final x = (i ~/ 4) % 1080, y = (i ~/ 4) ~/ 1080;
          expect(y, inInclusiveRange(250, 470));
          expect(x, inInclusiveRange(210, 870));
        }
      }
      expect(changed, greaterThan(5000));
      expect(
        lunar.windowVisible(room.withVisibility('window-left', false), 'left'),
        isFalse,
      );
      expect(
        lunar.windowVisible(room.withVisibility('window-left', false), 'right'),
        isTrue,
      );
      for (final image in decoded.values) {
        image.dispose();
      }
    },
  );
  testWidgets(
    'native furniture controls save the chosen facing and reusable frame',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var selected = const RoomFurnishings().withSet(FurnitureStyle.lunar);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FurnitureStore(
                initial: selected,
                onChanged: (next) async {
                  await next.save('native-ui');
                  selected = next;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final facing = find.byKey(const Key('lunar-facing-desk-x'));
      await tester.ensureVisible(facing);
      await tester.tap(facing);
      await tester.pump(const Duration(milliseconds: 500));
      expect(selected.facings['desk'], 'x');
      final frame = find.byKey(const Key('lunar-frame-square'));
      await tester.ensureVisible(frame);
      await tester.tap(frame);
      await tester.pump(const Duration(milliseconds: 500));
      expect((await RoomFurnishings.load('native-ui')).frameTemplate, 'square');
      expect(tester.takeException(), isNull);
    },
  );
}
