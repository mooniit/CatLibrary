import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/travel/travel_repository.dart';

void main() {
  test('lost travel receipt survives restart and never pays twice', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    Map<String, dynamic>? receipt;
    var debits = 0;
    Future<Map<String, dynamic>> rpc(
      String action,
      Map<String, dynamic> args,
    ) async {
      if (action == 'travel_request') return receipt ?? {'status': 'not_found'};
      debits++;
      receipt = {
        'status': 'started',
        'request_id': args['request_id'],
        'family_id': 'F',
      };
      throw TimeoutException('receipt lost');
    }

    final repo = TravelRepository(db, 'A', rpc: rpc);
    await expectLater(repo.start('F', 'cat'), throwsA(isA<TimeoutException>()));
    await expectLater(repo.start('F', 'different-cat'), throwsStateError);
    expect(await TravelRepository(db, 'B').pending(), isNull);
    final reopened = TravelRepository(db, 'A', rpc: rpc);
    expect((await reopened.reconcile())!['status'], 'started');
    expect(await reopened.pending(), isNull);
    expect(debits, 1);
  });
  test(
    'unverifiable receipt keeps pending request; explicit rejection clears it',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var valid = false;
      final repo = TravelRepository(
        db,
        'A',
        rpc: (action, args) async => action == 'travel_request'
            ? {'status': 'not_found'}
            : {
                'status': 'rejected',
                'request_id': valid ? args['request_id'] : 'wrong',
                'reason': 'insufficient_gems',
              },
      );
      await expectLater(repo.start('F', 'cat'), throwsStateError);
      expect(await repo.pending(), isNotNull);
      valid = true;
      expect((await repo.reconcile())!['reason'], 'insufficient_gems');
      expect(await repo.pending(), isNull);
    },
  );
  test(
    'album cache scoped to owner and latest family; leaving hides cache',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      String? family = 'F';
      final repo = TravelRepository(
        db,
        'A',
        rpc: (_, _) async => {
          'family_id': family,
          'photos': [
            {'id': 'photo'},
          ],
        },
      );
      await repo.load(album: true);
      expect((await repo.cached(album: true))!['photos'], hasLength(1));
      expect(await TravelRepository(db, 'B').cached(album: true), isNull);
      family = null;
      await repo.load(album: true);
      expect(await repo.cached(album: true), isNull);
    },
  );
}
