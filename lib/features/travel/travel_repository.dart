import '../../core/storage/app_database.dart';
import '../shop/shop_repository.dart';

/// Reuses the owner/family scoped JSON storage; travel keys cannot collide with room drafts.
class TravelRepository {
  TravelRepository(this.database, this.ownerId, {FurnitureRpc? rpc})
    : _cloud = ShopRepository(database, ownerId, rpc: rpc);
  final AppDatabase database;
  final String ownerId;
  final ShopRepository _cloud;
  Future<Map<String, dynamic>> call(String action, Map<String, dynamic> args) =>
      _cloud.call(action, args);
  Future<Map<String, dynamic>?> pending() =>
      database.furnitureLocal(ownerId, 'travel', 'pending');
  bool _busy = false;
  Future<Map<String, dynamic>> start(String family, String cat) async {
    if (_busy) throw StateError('正在核对旅行');
    _busy = true;
    try {
      var request = await pending();
      if (request != null &&
          (request['target_family'] != family ||
              request['target_cat'] != cat)) {
        throw StateError('请先核对上次旅行');
      }
      request ??= {
        'request_id': furnitureRequestId(),
        'target_family': family,
        'target_cat': cat,
      };
      await database.putFurnitureLocal(ownerId, 'travel', 'pending', request);
      return await _resolve(request);
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>?> reconcile() async {
    if (_busy) throw StateError('正在核对旅行');
    _busy = true;
    try {
      final request = await pending();
      return request == null ? null : await _resolve(request);
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>> _resolve(Map<String, dynamic> request) async {
    var result = await call('travel_request', {
      'target_request': request['request_id'],
    });
    if (result['status'] == 'not_found') {
      result = await call('start_cat_travel', request);
    }
    if (!['started', 'rejected'].contains(result['status']) ||
        result['request_id'] != request['request_id'] ||
        (result['status'] == 'started' &&
            result['family_id'] != request['target_family'])) {
      throw StateError('无法核对旅行回执');
    }
    await database.transaction(() async {
      await database.putFurnitureLocal(ownerId, 'travel', 'receipt', result);
      await database.removeFurnitureLocal(ownerId, 'travel', 'pending');
    });
    return result;
  }

  Future<Map<String, dynamic>> load({bool album = false}) async {
    final raw = await call(album ? 'family_album' : 'travel_state', {});
    final kind = album ? 'album' : 'state';
    await database.putFurnitureLocal(ownerId, 'travel', '${kind}_index', {
      'family_id': raw['family_id'],
    });
    if (raw['family_id'] != null) {
      await database.putFurnitureLocal(
        ownerId,
        raw['family_id'],
        'travel_$kind',
        raw,
      );
    }
    return raw;
  }

  Future<Map<String, dynamic>?> cached({bool album = false}) async {
    final kind = album ? 'album' : 'state';
    final index = await database.furnitureLocal(
      ownerId,
      'travel',
      '${kind}_index',
    );
    return index?['family_id'] == null
        ? null
        : database.furnitureLocal(ownerId, index!['family_id'], 'travel_$kind');
  }
}
