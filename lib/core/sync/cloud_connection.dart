import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum CloudPhase {
  unknown,
  checking,
  online,
  offline,
  serviceUnavailable,
  authenticationRequired,
  unconfigured,
}

class CloudStatus {
  const CloudStatus(this.phase, {this.verifiedAt});
  final CloudPhase phase;
  final DateTime? verifiedAt;
  String get label => switch (phase) {
    CloudPhase.online => '已连接',
    CloudPhase.checking => '正在连接',
    CloudPhase.offline => '离线保存中',
    CloudPhase.serviceUnavailable => '服务暂不可用',
    CloudPhase.authenticationRequired => '身份连接待核对',
    CloudPhase.unconfigured => '尚未连接服务',
    CloudPhase.unknown => '等待连接',
  };
}

/// Evidence comes from actual server responses, never a cached session or Wi-Fi.
class CloudConnection extends ValueNotifier<CloudStatus> {
  CloudConnection() : super(const CloudStatus(CloudPhase.unknown));
  int _issued = 0, _lastEvidence = 0;
  int begin() {
    if (value.phase == CloudPhase.unknown) {
      value = const CloudStatus(CloudPhase.checking);
    }
    return ++_issued;
  }

  void response(int id, int code) {
    if (id < _lastEvidence) return;
    _lastEvidence = id;
    final phase = code >= 500
        ? CloudPhase.serviceUnavailable
        : code == 401
        ? CloudPhase.authenticationRequired
        : CloudPhase.online;
    value = CloudStatus(phase, verifiedAt: DateTime.now());
  }

  void failed(int id) {
    if (id < _lastEvidence) return;
    _lastEvidence = id;
    value = CloudStatus(CloudPhase.offline, verifiedAt: value.verifiedAt);
  }

  void unconfigured() => value = const CloudStatus(CloudPhase.unconfigured);

  static bool isLocalEndpoint(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'localhost' ||
        host == '::1' ||
        host.startsWith('127.') ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(host);
  }
}

/// Request IDs only order observations; financial retries keep their own UUIDs.
class ConnectionHttpClient extends http.BaseClient {
  ConnectionHttpClient(
    this.delegate,
    this.connection, {
    this.timeout = const Duration(seconds: 12),
  });
  final http.Client delegate;
  final CloudConnection connection;
  final Duration timeout;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = connection.begin();
    final deadline = request.url.path.startsWith('/storage/')
        ? const Duration(seconds: 60)
        : timeout;
    try {
      final response = await delegate.send(request).timeout(deadline);
      connection.response(id, response.statusCode);
      final stream = response.stream
          .timeout(deadline)
          .transform<List<int>>(
            StreamTransformer.fromHandlers(
              handleData: (data, sink) => sink.add(data),
              handleError: (Object error, StackTrace trace, sink) {
                connection.failed(id);
                sink.addError(error, trace);
              },
            ),
          );
      return http.StreamedResponse(
        stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      connection.failed(id);
      rethrow;
    }
  }

  @override
  void close() => delegate.close();
}
