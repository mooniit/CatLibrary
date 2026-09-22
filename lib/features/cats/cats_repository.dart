import '../../core/sync/cloud_client.dart';

class CatsRepository {
  static Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> arguments,
  ) async {
    final client = await CloudClient.connect();
    return Map<String, dynamic>.from(
      await client.rpc(action, params: arguments) as Map,
    );
  }
}
