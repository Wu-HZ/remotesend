import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/gotify_models.dart';

class GotifyException implements Exception {
  const GotifyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GotifyMessagePage {
  const GotifyMessagePage({required this.messages, this.nextSince});

  final List<GotifyMessage> messages;
  final int? nextSince;
}

/// REST and WebSocket transport for a Gotify server.
class GotifyService {
  GotifyService(this.config)
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.json,
        ),
      );

  final GotifyConfig config;
  final Dio _dio;
  final StreamController<GotifyMessage> _messages =
      StreamController<GotifyMessage>.broadcast();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  bool _closed = false;

  Stream<GotifyMessage> get messages => _messages.stream;

  Future<void> connect() async {
    if (!config.isConfigured) {
      throw const GotifyException('Gotify is not configured');
    }

    final uri = _endpoint(
      '/stream',
      webSocket: true,
      queryParameters: {'token': config.clientToken.trim()},
    );

    try {
      final socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 15));
      if (_closed) {
        await socket.close();
        return;
      }

      socket.pingInterval = const Duration(seconds: 30);
      _socket = socket;
      _socketSubscription = socket.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String);
            if (decoded is Map) {
              _messages.add(
                GotifyMessage.fromJson(Map<String, dynamic>.from(decoded)),
              );
            }
          } catch (_) {
            // Ignore malformed or non-message frames.
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_messages.isClosed) {
            _messages.addError(error, stackTrace);
          }
        },
        onDone: () {
          if (!_messages.isClosed) {
            _messages.close();
          }
        },
        cancelOnError: true,
      );
    } catch (error) {
      throw GotifyException('Failed to connect to Gotify: $error');
    }
  }

  Future<GotifyMessagePage> fetchMessages({int limit = 200, int? since}) async {
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        _endpoint(
          '/message',
          queryParameters: {
            'limit': '$limit',
            if (since != null) 'since': '$since',
          },
        ),
        options: Options(headers: _tokenHeader(config.clientToken)),
      );
      final data = response.data ?? const <String, dynamic>{};
      final rawMessages = data['messages'] as List<dynamic>? ?? const [];
      final messages = rawMessages
          .whereType<Map>()
          .map(
            (item) => GotifyMessage.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
      final paging = data['paging'] is Map
          ? Map<String, dynamic>.from(data['paging'] as Map)
          : const <String, dynamic>{};
      final nextSinceValue = (paging['since'] as num?)?.toInt() ?? 0;
      return GotifyMessagePage(
        messages: messages,
        nextSince: nextSinceValue > 0 ? nextSinceValue : null,
      );
    } on DioException catch (error) {
      throw GotifyException(_dioMessage(error));
    }
  }

  Future<GotifyMessage> send({
    required RemoteSendEvent event,
    required String title,
    required String message,
    int priority = 0,
  }) async {
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        _endpoint('/message'),
        data: {
          'title': title,
          'message': message,
          'priority': priority,
          'extras': event.toExtras(),
        },
        options: Options(
          headers: {
            ..._tokenHeader(config.appToken),
            Headers.contentTypeHeader: Headers.jsonContentType,
          },
        ),
      );
      return GotifyMessage.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw GotifyException(_dioMessage(error));
    }
  }

  /// Validates both tokens without creating a notification.
  static Future<void> testConfiguration(GotifyConfig config) async {
    if (!config.hasCredentials) {
      throw const GotifyException('Gotify URL and both tokens are required');
    }

    final service = GotifyService(config.copyWith(enabled: true));
    try {
      await service.fetchMessages(limit: 1);
      await service.send(
        event: RemoteSendEvent(
          type: 'connection_test',
          senderDeviceId: config.deviceId,
          senderName: 'RemoteSend',
          payload: {'platform': Platform.operatingSystem},
        ),
        title: 'RemoteSend connection test',
        message: 'Gotify connection is ready',
        priority: -2,
      );
      await service.connect();
    } finally {
      await service.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socketSubscription?.cancel();
    await _socket?.close();
    _dio.close(force: true);
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }

  Uri _endpoint(
    String endpoint, {
    bool webSocket = false,
    Map<String, String>? queryParameters,
  }) {
    final base = Uri.parse(config.serverUrl.trim());
    final basePath = base.path.replaceAll(RegExp(r'/+$'), '');
    final endpointPath = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return base.replace(
      scheme: webSocket
          ? (base.scheme.toLowerCase() == 'https' ? 'wss' : 'ws')
          : base.scheme,
      path: '$basePath$endpointPath',
      queryParameters: queryParameters,
      fragment: null,
    );
  }

  static Map<String, String> _tokenHeader(String token) => {
    'X-Gotify-Key': token.trim(),
  };

  static String _dioMessage(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    if (status != null) {
      return 'Gotify HTTP $status${body == null ? '' : ': $body'}';
    }
    return 'Gotify request failed: ${error.message ?? error.type.name}';
  }
}
