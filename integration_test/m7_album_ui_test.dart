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

  testWidgets('travel batch 4 and all twelve pairs render in both themes', (
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
                (
                  'longhair-eiffel',
                  '白云',
                  'light_long',
                  'eiffel',
                  '埃菲尔铁塔',
                  '埃菲尔铁塔',
                ),
                (
                  'calico-liberty',
                  '橘点',
                  'black_short',
                  'liberty',
                  '自由女神像',
                  '自由女神像',
                ),
                (
                  'longhair-liberty',
                  '白云',
                  'light_long',
                  'liberty',
                  '自由女神像',
                  '自由女神像',
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
      await binding.takeScreenshot('m7-album-batch4-$mode');
      measurements.add({
        'theme': mode,
        'view': 'album',
        'initialRenderMs': initialLoad.elapsedMilliseconds,
        'decodedImageCacheBytes':
            PaintingBinding.instance.imageCache.currentSizeBytes,
      });
      for (final id in [
        'longhair-eiffel',
        'calico-liberty',
        'longhair-liberty',
      ]) {
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
    final fullPhotos = <Map<String, dynamic>>[
      for (final destination in [
        ('palace', '故宫', '故宫宫殿'),
        ('louvre', '卢浮宫', '维纳斯雕像'),
        ('fuji', '富士山', '富士山'),
        ('pyramid', '金字塔', '埃及金字塔'),
        ('eiffel', '埃菲尔铁塔', '埃菲尔铁塔'),
        ('liberty', '自由女神像', '自由女神像'),
      ])
        for (final cat in [
          ('black_short', '橘点', 'calico'),
          ('light_long', '白云', 'longhair'),
        ])
          {
            'id': 'full-${cat.$3}-${destination.$1}',
            'cat_name': cat.$2,
            'appearance': cat.$1,
            'destination': destination.$1,
            'destination_label': destination.$2,
            'souvenir_label': destination.$3,
            'taken_at': '2026-10-07T16:00:00Z',
            'arranger_label': '另一位成员',
            'arranged_by': 'private-visual-owner',
          },
    ];
    final completeAlbumViews = <Map<String, Object>>[];
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final mode = brightness == Brightness.light ? 'light' : 'night';
      final repository = TravelRepository(
        db,
        'visual-owner',
        rpc: (action, _) async {
          if (action != 'family_album') {
            throw StateError('Fixture refuses writes');
          }
          calls.add(action);
          return {'family_id': 'visual-family', 'photos': fullPhotos};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          debugShowCheckedModeBanner: false,
          home: AlbumPage(key: ValueKey('all12-$mode'), repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await waitForPaintedArt(tester, find.byType(Image).evaluate().length);
      expect(find.text('12 条旅行回忆'), findsOneWidget);
      await binding.takeScreenshot('m7-album-all12-top-$mode');
      for (final photo in fullPhotos) {
        final card = find.byKey(ValueKey('photo-${photo['id']}'));
        await tester.scrollUntilVisible(
          card,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
        await waitForPaintedArt(tester, 1);
        expect(find.text('旅行插画待收录'), findsNothing);
        expect(find.textContaining('private-visual-owner'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await waitForPaintedArt(tester, find.byType(Image).evaluate().length);
      await binding.takeScreenshot('m7-album-all12-bottom-$mode');
      completeAlbumViews.add({
        'theme': mode,
        'decodedDetailPairs': fullPhotos.length,
        'decodedImageCacheBytes':
            PaintingBinding.instance.imageCache.currentSizeBytes,
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    expect(calls, List.filled(4, 'family_album'));
    binding.reportData!.addAll({
      'nativeVisualTestPassed': true,
      'assetBatch': 4,
      'fixtureOnly': true,
      'measurements': measurements,
      'allTravelPairsRendered': true,
      'completeAlbumViews': completeAlbumViews,
      'remoteInternetVerified': false,
      'physicalPhoneVerified': false,
    });
  });
}
