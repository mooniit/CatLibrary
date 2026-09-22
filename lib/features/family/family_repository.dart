import '../../core/sync/cloud_client.dart';

class FamilyRepository {
  static Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> arguments,
  ) async {
    final client = await CloudClient.connect();
    final value = await client.rpc(action, params: arguments);
    return Map<String, dynamic>.from(value as Map);
  }
}
