import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/models/upload_queue.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/local_upload_api_provider.dart';
import 'package:remote_send/providers/pending_upload_provider.dart';
import 'package:remote_send/providers/upload_queue_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/local_upload_api_server.dart';
import 'package:remote_send/services/webdav_exceptions.dart';
import 'package:remote_send/services/webdav_service.dart';

class _Config extends ConfigNotifier {
  _Config(AppConfig config) : super(ConfigService()) {
    state = AsyncData(config);
  }

  @override
  Future<bool> updateConfig(AppConfig config) async {
    state = AsyncData(config);
    return true;
  }
}

class _Service extends WebDavService {
  final calls = <Completer<WebDavResult<bool>>>[];
  final paths = <String>[];

  @override
  Future<WebDavResult<bool>> uploadFileToPath(
    String localPath,
    String remotePath, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) {
    paths.add(remotePath);
    final pending = Completer<WebDavResult<bool>>();
    calls.add(pending);
    return pending.future;
  }
}

Future<(int, Map<String, dynamic>)> _call(
  int port,
  String method,
  String route, {
  String? token = 'secret',
  Map<String, Object?>? body,
  String? contentType,
  String? origin,
  String? host,
}) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$route'),
    );
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (origin != null) request.headers.set('origin', origin);
    if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
    if (body != null) {
      request.headers.contentType = ContentType.parse(
        contentType ?? 'application/json',
      );
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close();
    final result =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
    return (response.statusCode, result);
  } finally {
    client.close(force: true);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

void main() {
  test(
    'upload API configuration is off by default and survives copies/JSON',
    () {
      expect(AppConfig().localUploadApiEnabled, isFalse);
      expect(
        AppConfig.fromJson({'version': 13, 'servers': []}).localUploadApiToken,
        '',
      );
      final config = AppConfig(
        localUploadApiEnabled: true,
        localUploadApiToken: 'secret',
      );
      final decoded = AppConfig.fromJsonString(config.toJsonString());
      expect(decoded.localUploadApiEnabled, isTrue);
      expect(decoded.localUploadApiToken, 'secret');
      expect(decoded.copyWith(localName: 'new').localUploadApiToken, 'secret');
      expect(
        decoded
            .copyWithNullActiveServers(clearFiles: true)
            .localUploadApiEnabled,
        isTrue,
      );
      expect(decoded.copyWith(localUploadApiToken: 'rotated'), isNot(decoded));
    },
  );

  group('loopback HTTP API', () {
    late Directory temp;
    late File file;
    late LocalUploadApiServer server;
    var key = 'secret';
    final jobs = <String, UploadItem>{};

    setUp(() async {
      key = 'secret';
      jobs.clear();
      temp = await Directory.systemTemp.createTemp('remotesend_api_');
      file = File('${temp.path}${Platform.pathSeparator}artifact.apk');
      await file.writeAsString('build');
      server = await LocalUploadApiServer.bind(
        port: 0,
        token: () => key,
        enqueue: (path, overwrite) async {
          expect(path, file.path);
          final item = UploadItem(
            id: 'upload_1',
            localPath: path,
            remotePath: '/RemoteSend/Files/a.apk',
            fileName: 'a.apk',
            fileSize: 5,
            automated: true,
          );
          jobs[item.id] = item;
          return item;
        },
        lookup: (id) => jobs[id],
      );
    });
    tearDown(() async {
      await server.close();
      await temp.delete(recursive: true);
    });

    test('requires a token and rejects browser origins', () async {
      expect(
        (await _call(
          server.port,
          'GET',
          '/v1/uploads/upload_1',
          token: null,
        )).$1,
        401,
      );
      expect(
        (await _call(
          server.port,
          'GET',
          '/v1/uploads/upload_1',
          token: 'wrong',
        )).$1,
        401,
      );
      expect(
        (await _call(
          server.port,
          'GET',
          '/v1/uploads/upload_1',
          origin: 'https://bad.example',
        )).$1,
        403,
      );
      expect(
        (await _call(
          server.port,
          'GET',
          '/v1/uploads/upload_1',
          host: 'attacker.invalid',
        )).$1,
        403,
      );
      key = 'rotated';
      expect((await _call(server.port, 'GET', '/v1/uploads/upload_1')).$1, 401);
      expect(
        (await _call(
          server.port,
          'GET',
          '/v1/uploads/upload_1',
          token: key,
        )).$1,
        404,
      );
    });

    test(
      'accepts an absolute file and reports completion separately from 202',
      () async {
        final (status, queued) = await _call(
          server.port,
          'POST',
          '/v1/uploads',
          body: {'path': file.path},
        );
        expect(status, 202);
        expect(queued['status'], 'pending');
        final id = queued['id'] as String;
        jobs[id] = jobs[id]!.copyWith(
          status: UploadStatus.completed,
          progress: 1,
        );
        final (code, complete) = await _call(
          server.port,
          'GET',
          '/v1/uploads/$id',
        );
        expect(code, 200);
        expect(complete['status'], 'completed');
        expect(complete['progress'], 1);
        expect(
          (await _call(server.port, 'GET', '/v1/uploads/no-such-job')).$1,
          404,
        );
      },
    );

    test('validates local paths and request shapes', () async {
      expect(
        (await _call(
          server.port,
          'POST',
          '/v1/uploads',
          body: {'path': 'relative.apk'},
        )).$1,
        400,
      );
      expect(
        (await _call(
          server.port,
          'POST',
          '/v1/uploads',
          body: {'path': '${temp.path}/missing'},
        )).$1,
        400,
      );
      expect(
        (await _call(
          server.port,
          'POST',
          '/v1/uploads',
          body: {'path': file.path, 'overwrite': 'yes'},
        )).$1,
        400,
      );
      expect(
        (await _call(
          server.port,
          'POST',
          '/v1/uploads',
          body: {'path': file.path, 'extra': 1},
        )).$1,
        400,
      );
      expect(
        (await _call(
          server.port,
          'POST',
          '/v1/uploads',
          body: {'path': file.path},
          contentType: 'text/plain',
        )).$1,
        415,
      );
      expect(
        (await _call(
          server.port,
          'POST',
          '/v1/uploads',
          body: {'path': file.path, 'extra': List.filled(8192, 'x').join()},
        )).$1,
        413,
      );
    });
  });

  test(
    'controller starts only when enabled, tracks uploads and rotates tokens',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'remotesend_controller_',
      );
      final file = File('${temp.path}${Platform.pathSeparator}result.zip');
      await file.writeAsString('compiled');
      final server = ServerConfig(
        id: 'files',
        name: 'files',
        serverUrl: 'https://example.invalid',
        username: 'user',
        password: 'pass',
        createdAt: DateTime(2026),
      );
      final service = _Service();
      final config = AppConfig(
        servers: [server],
        activeFilesServerId: server.id,
        localUploadApiToken: 'secret',
      );
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith((ref) => _Config(config)),
          webDavFilesServiceProvider.overrideWithValue(service),
          localUploadApiPortProvider.overrideWithValue(0),
        ],
      );
      final listener = container.listen(localUploadApiProvider, (_, _) {});
      try {
        expect(container.read(localUploadApiProvider).running, isFalse);
        await container
            .read(configProvider.notifier)
            .updateConfig(config.copyWith(localUploadApiEnabled: true));
        await _until(() => container.read(localUploadApiProvider).running);
        final port = container.read(localUploadApiProvider).port!;
        final (accepted, created) = await _call(
          port,
          'POST',
          '/v1/uploads',
          body: {'path': file.path},
        );
        expect(accepted, 202);
        expect(created['remotePath'], startsWith('/RemoteSend/Files/result-'));
        expect(created['remotePath'], endsWith('.zip'));
        expect(service.paths.single, created['remotePath']);
        final id = created['id'] as String;
        expect(
          (await _call(port, 'GET', '/v1/uploads/$id')).$2['status'],
          'uploading',
        );
        service.calls.single.complete(
          const WebDavResult.failure(
            WebDavConnectionException(message: 'offline'),
          ),
        );
        await _until(
          () =>
              container.read(uploadQueueProvider).items.single.status ==
              UploadStatus.failed,
        );
        container.read(uploadQueueProvider.notifier).clearAll();
        final (_, finalJob) = await _call(port, 'GET', '/v1/uploads/$id');
        expect(finalJob['status'], 'failed');
        expect(finalJob['error'], isNotNull);

        final (secondStatus, second) = await _call(
          port,
          'POST',
          '/v1/uploads',
          body: {'path': file.path, 'overwrite': true},
        );
        expect(secondStatus, 202);
        expect(second['remotePath'], '/RemoteSend/Files/result.zip');
        service.calls[1].complete(const WebDavResult.success(true));
        final nextId = second['id'] as String;
        await _until(
          () =>
              container.read(uploadQueueProvider).items.single.status ==
              UploadStatus.completed,
        );
        container.read(uploadQueueProvider.notifier).clearAll();
        expect(
          (await _call(port, 'GET', '/v1/uploads/$nextId')).$2['status'],
          'completed',
        );

        await container
            .read(configProvider.notifier)
            .updateConfig(
              config.copyWith(
                localUploadApiEnabled: true,
                localUploadApiToken: 'rotated',
              ),
            );
        expect((await _call(port, 'GET', '/v1/uploads/$id')).$1, 401);
        expect(
          (await _call(port, 'GET', '/v1/uploads/$id', token: 'rotated')).$1,
          200,
        );
        await container.read(configProvider.notifier).updateConfig(config);
        await _until(() => !container.read(localUploadApiProvider).running);
      } finally {
        listener.close();
        container.dispose();
        await temp.delete(recursive: true);
      }
    },
  );

  test('manual connection fallback does not consume queued API jobs', () async {
    final temp = await Directory.systemTemp.createTemp('remotesend_mixed_');
    final file = File('${temp.path}${Platform.pathSeparator}mixed.apk');
    await file.writeAsString('build');
    final server = ServerConfig(
      id: 'files',
      name: 'files',
      serverUrl: 'https://example.invalid',
      username: 'user',
      password: 'pass',
      createdAt: DateTime(2026),
    );
    final service = _Service();
    final container = ProviderContainer(
      overrides: [
        configProvider.overrideWith(
          (ref) => _Config(
            AppConfig(servers: [server], activeFilesServerId: server.id),
          ),
        ),
        webDavFilesServiceProvider.overrideWithValue(service),
      ],
    );
    try {
      final queue = container.read(uploadQueueProvider.notifier);
      await queue.addFiles([file.path]);
      final id = await queue.addAutomatedFile(
        file.path,
        remoteName: 'unique.apk',
      );
      expect(service.calls.length, 1);
      service.calls.first.complete(
        const WebDavResult.failure(
          WebDavConnectionException(message: 'offline'),
        ),
      );
      await _until(() => service.calls.length == 2);
      expect(container.read(pendingUploadProvider).filePaths, [file.path]);
      expect(container.read(uploadQueueProvider).items.single.id, id);
      expect(container.read(uploadQueueProvider).totalBytes, 5);
      service.calls.last.complete(
        const WebDavResult.failure(
          WebDavConnectionException(message: 'offline'),
        ),
      );
      await _until(
        () =>
            container.read(uploadQueueProvider).items.single.status ==
            UploadStatus.failed,
      );
      expect(container.read(pendingUploadProvider).filePaths, [file.path]);
    } finally {
      container.dispose();
      await temp.delete(recursive: true);
    }
  });

  test(
    'automated queue jobs remain failed, rather than silently falling back to UI',
    () async {
      final temp = await Directory.systemTemp.createTemp('remotesend_queue_');
      final file = File('${temp.path}${Platform.pathSeparator}build.apk');
      await file.writeAsString('build');
      final server = ServerConfig(
        id: 'files',
        name: 'files',
        serverUrl: 'https://example.invalid',
        username: 'user',
        password: 'pass',
        createdAt: DateTime(2026),
      );
      final service = _Service();
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith(
            (ref) => _Config(
              AppConfig(servers: [server], activeFilesServerId: server.id),
            ),
          ),
          webDavFilesServiceProvider.overrideWithValue(service),
        ],
      );
      try {
        final queue = container.read(uploadQueueProvider.notifier);
        final id = await queue.addAutomatedFile(
          file.path,
          remoteName: 'build-unique.apk',
        );
        expect(id, isNotNull);
        expect(
          container.read(uploadQueueProvider).items.single.status,
          UploadStatus.uploading,
        );
        expect(service.paths.single, '/RemoteSend/Files/build-unique.apk');
        service.calls.single.complete(
          const WebDavResult.failure(
            WebDavConnectionException(message: 'offline'),
          ),
        );
        await _until(
          () =>
              container.read(uploadQueueProvider).items.single.status ==
              UploadStatus.failed,
        );
        expect(container.read(uploadQueueProvider).items.single.id, id);
        expect(container.read(pendingUploadProvider).filePaths, isEmpty);
      } finally {
        container.dispose();
        await temp.delete(recursive: true);
      }
    },
  );
}
