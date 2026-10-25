import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/upload_queue.dart';

/// This API accepts local file paths, not file bytes. It must only run on a
/// desktop loopback interface, with an explicit opt-in and a separate token.
class LocalUploadApiServer {
  static const int defaultPort = 38764;
  static const int _maxBodyBytes = 8192;

  final HttpServer _http;
  final String Function() token;
  final Future<UploadItem> Function(String path, bool overwrite) enqueue;
  final UploadItem? Function(String id) lookup;

  LocalUploadApiServer._(this._http, this.token, this.enqueue, this.lookup) {
    _http.listen(_handle);
  }

  int get port => _http.port;

  static Future<LocalUploadApiServer> bind({
    required String Function() token,
    required Future<UploadItem> Function(String path, bool overwrite) enqueue,
    required UploadItem? Function(String id) lookup,
    InternetAddress? address,
    int port = defaultPort,
  }) async {
    final http = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    return LocalUploadApiServer._(http, token, enqueue, lookup);
  }

  Future<void> close() async {
    await _http.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      // Reject DNS rebinding / browser-originated requests even on loopback.
      if (request.connectionInfo?.remoteAddress.isLoopback != true ||
          request.headers.value(HttpHeaders.hostHeader) != '127.0.0.1:$port' ||
          request.headers.value('origin') != null) {
        throw const LocalUploadApiException(403, 'Local CLI requests only');
      }
      final expected = token();
      if (expected.isEmpty ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $expected') {
        throw const LocalUploadApiException(401, 'Invalid API token');
      }
      if (request.method == 'POST' && request.uri.path == '/v1/uploads') {
        if (request.headers.contentType?.mimeType != 'application/json') {
          throw const LocalUploadApiException(415, 'Expected application/json');
        }
        if (request.contentLength > _maxBodyBytes) {
          throw const LocalUploadApiException(413, 'Request body too large');
        }
        final bytes = <int>[];
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > _maxBodyBytes) {
            throw const LocalUploadApiException(413, 'Request body too large');
          }
        }
        dynamic input;
        try {
          input = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          throw const LocalUploadApiException(400, 'Invalid JSON');
        }
        if (input is! Map<String, dynamic> ||
            input.keys.any((key) => key != 'path' && key != 'overwrite') ||
            input['path'] is! String ||
            (input.containsKey('overwrite') && input['overwrite'] is! bool)) {
          throw const LocalUploadApiException(
            400,
            'Expected path and optional overwrite',
          );
        }
        final path = input['path'] as String;
        if (!p.isAbsolute(path) ||
            path.contains('\u0000') ||
            !await File(path).exists()) {
          throw const LocalUploadApiException(
            400,
            'Path must be an existing absolute file',
          );
        }
        final item = await enqueue(path, input['overwrite'] == true);
        await _reply(request, 202, _itemJson(item));
        return;
      }
      if (request.method == 'GET' &&
          request.uri.pathSegments.length == 3 &&
          request.uri.pathSegments[0] == 'v1' &&
          request.uri.pathSegments[1] == 'uploads') {
        final item = lookup(request.uri.pathSegments[2]);
        if (item == null) {
          throw const LocalUploadApiException(404, 'Unknown upload ID');
        }
        await _reply(request, 200, _itemJson(item));
        return;
      }
      throw const LocalUploadApiException(404, 'Unknown endpoint');
    } on LocalUploadApiException catch (e) {
      await _reply(request, e.status, {'error': e.message});
    } catch (_) {
      // Never echo exceptions containing local paths, tokens or server secrets.
      await _reply(request, 500, {'error': 'Internal upload API error'});
    }
  }

  static Map<String, Object?> _itemJson(UploadItem item) => {
    'id': item.id,
    'status': item.status.name,
    'progress': item.progress,
    'fileName': item.fileName,
    'remotePath': item.remotePath,
    if (item.error != null) 'error': item.error,
  };

  static Future<void> _reply(
    HttpRequest request,
    int code,
    Map<String, Object?> data,
  ) async {
    try {
      final response = request.response;
      response.statusCode = code;
      response.headers.contentType = ContentType.json;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.write(jsonEncode(data));
      await response.close();
    } catch (_) {
      // The client may already have closed the connection. Do not turn a
      // disconnected caller into an unhandled server-side async error.
    }
  }
}

class LocalUploadApiException implements Exception {
  final int status;
  final String message;
  const LocalUploadApiException(this.status, this.message);
}
