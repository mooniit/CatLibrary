import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/album/album_page.dart';
import 'package:cat_library_demo/features/travel/travel_repository.dart';

// Isolated visual records only; never creates a real visit or inventory item.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> waitForPaintedArt(WidgetTester tester, int count) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      if (images.length == count &&
          images.every((image) => image.image != null)) {
        await tester.pump(const Duration(milliseconds: 200));
        return;
      }
    }
    fail('Travel artwork did not produce decoded image frames');
  }

  testWidgets('travel batch 1 renders complete art and source in both themes', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var converted = false;
    final calls = <String>[];
    final measurements = <Map<String, Object>>[];
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final mode = brightness == Brightness.light ? 'light' : 'night';
      final repository = TravelRepository(
        db,
        'visual-owner',
        rpc: (action, _) async {
          calls.add(action);
          if (action != 'family_album') {
            throw StateError('Visual fixture refuses writes');
          }
          return {
            'family_id': 'visual-family',
            'photos': [
              for (final record in [
                ('calico-palace', '橘点', 'black_short', 'palace', '故宫', '故宫宫殿'),
                ('longhair-palace', '白云', 'light_long', 'palace', '故宫', '故宫宫殿'),
                (
                  'calico-louvre',
                  '橘点',
                  'black_short',
                  'louvre',
                  '卢浮宫',
                  '维纳斯雕像',
                ),
              ])
                {
                  'id': record.$1,
                  'cat_name': record.$2,
                  'appearance': record.$3,
                  'destination': record.$4,
                  'destination_label': record.$5,
                  'souvenir_label': record.$6,
                  'taken_at': '2026-10-07T16:00:00Z',
                  'arranger_label': '另一位成员',
                  'arranged_by': 'private-visual-owner',
                },
            ],
          };
        },
      );
      final initialLoad = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          debugShowCheckedModeBanner: false,
          home: AlbumPage(key: ValueKey(mode), repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await waitForPaintedArt(tester, 3);
      initialLoad.stop();
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.text('旅行插画待收录'), findsNothing);
      await binding.takeScreenshot('m7-album-batch1-$mode');
      measurements.add({
        'theme': mode,
        'view': 'album',
        'initialRenderMs': initialLoad.elapsedMilliseconds,
        'decodedImageCacheBytes':
            PaintingBinding.instance.imageCache.currentSizeBytes,
      });
      for (final id in ['calico-palace', 'longhair-palace', 'calico-louvre']) {
        await tester.tap(find.byKey(ValueKey('photo-$id')));
        await tester.pumpAndSettle();
        await waitForPaintedArt(tester, 1);
        expect(find.textContaining('private-visual-owner'), findsNothing);
        await binding.takeScreenshot('m7-album-$id-detail-$mode');
        measurements.add({
          'theme': mode,
          'view': id,
          'decodedImageCacheBytes':
              PaintingBinding.instance.imageCache.currentSizeBytes,
        });
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    expect(calls, ['family_album', 'family_album']);
    binding.reportData!.addAll({
      'nativeVisualTestPassed': true,
      'fixtureOnly': true,
      'measurements': measurements,
      'remoteInternetVerified': false,
      'physicalPhoneVerified': false,
    });
  });
}
