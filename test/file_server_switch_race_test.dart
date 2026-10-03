import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/services/config_service.dart';
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

class _PendingService extends WebDavService {
  final lists = <Completer<WebDavResult<List<RemoteFile>>>>[];
  final checks = <Completer<WebDavResult<bool>>>[];
  final deletes = <Completer<WebDavResult<bool>>>[];
  final paths = <String?>[];

  @override
  Future<WebDavResult<List<RemoteFile>>> listFiles([String? subPath]) {
    paths.add(subPath);
    final pending = Completer<WebDavResult<List<RemoteFile>>>();
    lists.add(pending);
    return pending.future;
  }

  @override
  Future<WebDavResult<bool>> testConnection() {
    final pending = Completer<WebDavResult<bool>>();
    checks.add(pending);
    return pending.future;
  }

  @override
  Future<WebDavResult<bool>> deleteFile(String remoteName) {
    final pending = Completer<WebDavResult<bool>>();
    deletes.add(pending);
    return pending.future;
  }
}

const _failed = WebDavConnectionException(
  message: 'old server timed out',
  userMessage: 'Old server error',
);

void main() {
  final old = ServerConfig(
    id: 'old',
    name: 'Invalid',
    serverUrl: 'https://old.invalid',
    username: 'user',
    password: 'password',
    createdAt: DateTime(2026),
  );
  final valid = ServerConfig(
    id: 'valid',
    name: 'Valid',
    serverUrl: 'https://valid.example',
    username: 'user',
    password: 'password',
    createdAt: DateTime(2026),
  );

  late ProviderContainer container;
  late _PendingService service;
  setUp(() {
    service = _PendingService();
    container = ProviderContainer(
      overrides: [
        configProvider.overrideWith(
          (ref) => _Config(
            AppConfig(servers: [old, valid], activeFilesServerId: old.id),
          ),
        ),
        webDavFilesServiceProvider.overrideWithValue(service),
      ],
    );
    // Keep both providers alive while switching, as the file page does.
    container.listen(fileListProvider, (_, _) {});
    container.listen(filesConnectionStatusProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test(
    'startup retries transient failures and connects without a manual test',
    () async {
      final connection = container.read(filesConnectionStatusProvider.notifier);
      final pending = connection.testConnection(
        maxAttempts: 3,
        retryDelay: Duration.zero,
      );
      service.checks[0].complete(const WebDavResult.failure(_failed));
      for (var i = 0; i < 20 && service.checks.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        container.read(filesConnectionStatusProvider).state,
        WebDavConnectionState.connecting,
      );
      service.checks[1].complete(const WebDavResult.failure(_failed));
      for (var i = 0; i < 20 && service.checks.length < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      service.checks[2].complete(const WebDavResult.success(true));
      expect(await pending, isTrue);
      expect(service.checks.length, 3);
      expect(
        container.read(filesConnectionStatusProvider).state,
        WebDavConnectionState.connected,
      );
    },
  );

  test(
    'transient file-list error retries without erasing existing files',
    () async {
      final files = container.read(fileListProvider.notifier);
      final refresh = files.refresh(retryDelay: Duration.zero);
      service.lists[0].complete(const WebDavResult.failure(_failed));
      for (var i = 0; i < 20 && service.lists.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      const item = RemoteFile(
        name: 'available.txt',
        path: '/available.txt',
        isDirectory: false,
      );
      service.lists[1].complete(const WebDavResult.success([item]));
      expect(await refresh, isTrue);
      expect(container.read(fileListProvider).error, isNull);
      expect(
        container.read(fileListProvider).files.single.name,
        'available.txt',
      );
    },
  );

  test('startup does not retry authentication errors', () async {
    final connection = container.read(filesConnectionStatusProvider.notifier);
    final pending = connection.testConnection(
      maxAttempts: 3,
      retryDelay: Duration.zero,
    );
    service.checks.single.complete(
      const WebDavResult.failure(
        WebDavAuthException(message: 'wrong credentials'),
      ),
    );
    expect(await pending, isFalse);
    expect(service.checks.length, 1);
    expect(
      container.read(filesConnectionStatusProvider).state,
      WebDavConnectionState.error,
    );
  });

  test('server switch stops pending startup retries', () async {
    final connection = container.read(filesConnectionStatusProvider.notifier);
    final pending = connection.testConnection(
      maxAttempts: 3,
      retryDelay: const Duration(milliseconds: 20),
    );
    service.checks.single.complete(const WebDavResult.failure(_failed));
    await Future<void>.delayed(Duration.zero);
    await container.read(configProvider.notifier).switchFilesServer(valid.id);
    expect(await pending, isFalse);
    expect(service.checks.length, 1);
    expect(
      container.read(filesConnectionStatusProvider).state,
      WebDavConnectionState.disconnected,
    );
  });

  test(
    'late old-server failure cannot erase the new server files or status',
    () async {
      final files = container.read(fileListProvider.notifier);
      final connection = container.read(filesConnectionStatusProvider.notifier);
      final oldRefresh = files.refresh();
      final oldCheck = connection.testConnection();

      await container.read(configProvider.notifier).switchFilesServer(valid.id);
      expect(container.read(fileListProvider).files, isEmpty);
      expect(
        container.read(filesConnectionStatusProvider).state,
        WebDavConnectionState.disconnected,
      );

      final newCheck = connection.testConnection();
      service.checks[1].complete(const WebDavResult.success(true));
      expect(await newCheck, isTrue);
      final newRefresh = files.refresh();
      const item = RemoteFile(
        name: 'new.txt',
        path: '/new.txt',
        isDirectory: false,
      );
      service.lists[1].complete(const WebDavResult.success([item]));
      expect(await newRefresh, isTrue);

      service.checks[0].complete(const WebDavResult.failure(_failed));
      service.lists[0].complete(const WebDavResult.failure(_failed));
      expect(await oldCheck, isFalse);
      expect(await oldRefresh, isFalse);
      expect(
        container.read(filesConnectionStatusProvider).state,
        WebDavConnectionState.connected,
      );
      final current = container.read(fileListProvider);
      expect(current.files.map((file) => file.name), ['new.txt']);
      expect(current.isLoading, isFalse);
      expect(current.error, isNull);
    },
  );

  test(
    'late old-server success and same-server older refresh are ignored',
    () async {
      final files = container.read(fileListProvider.notifier);
      final oldRefresh = files.refresh();
      await container.read(configProvider.notifier).switchFilesServer(valid.id);
      // Materialize the provider after the server change, as a listening widget does.
      container.read(fileListProvider);
      final activeFiles = container.read(fileListProvider.notifier);
      expect(identical(files, activeFiles), isTrue);
      final first = activeFiles.refresh();
      final latest = activeFiles.refresh();
      const current = RemoteFile(
        name: 'current.txt',
        path: '/current.txt',
        isDirectory: false,
      );
      service.lists[2].complete(const WebDavResult.success([current]));
      expect(await latest, isTrue);
      expect(container.read(fileListProvider).files.single.name, 'current.txt');
      service.lists[1].complete(const WebDavResult.failure(_failed));
      service.lists[0].complete(const WebDavResult.success([]));
      expect(await first, isFalse);
      expect(await oldRefresh, isFalse);
      expect(container.read(fileListProvider).files.single.name, 'current.txt');
      expect(container.read(fileListProvider).error, isNull);
    },
  );

  test(
    'late old-server success cannot mark a failed new server connected',
    () async {
      final connection = container.read(filesConnectionStatusProvider.notifier);
      final oldCheck = connection.testConnection();
      await container.read(configProvider.notifier).switchFilesServer(valid.id);
      container.read(filesConnectionStatusProvider);
      final newCheck = connection.testConnection();
      service.checks[1].complete(const WebDavResult.failure(_failed));
      expect(await newCheck, isFalse);
      service.checks[0].complete(const WebDavResult.success(true));
      expect(await oldCheck, isFalse);
      final status = container.read(filesConnectionStatusProvider);
      expect(status.state, WebDavConnectionState.error);
      expect(status.errorMessage, 'Old server error');
    },
  );

  test(
    'old-server delete completion cannot remove a new-server file',
    () async {
      final files = container.read(fileListProvider.notifier);
      final oldDelete = files.deleteFile('shared.txt');
      await container.read(configProvider.notifier).switchFilesServer(valid.id);
      container.read(fileListProvider);
      final currentRefresh = files.refresh();
      const item = RemoteFile(
        name: 'shared.txt',
        path: '/shared.txt',
        isDirectory: false,
      );
      service.lists.single.complete(const WebDavResult.success([item]));
      expect(await currentRefresh, isTrue);
      service.deletes.single.complete(const WebDavResult.success(true));
      expect(await oldDelete, isFalse);
      expect(container.read(fileListProvider).files.single.name, 'shared.txt');
    },
  );

  test(
    'folder navigation is invalidated by a switch and an ordinary failure reverts path',
    () async {
      final files = container.read(fileListProvider.notifier);
      final oldNavigation = files.navigateToFolder('old-folder');
      await container.read(configProvider.notifier).switchFilesServer(valid.id);
      expect(container.read(fileListProvider).currentPath, '');
      final currentNavigation = files.navigateToFolder('new-folder');
      service.lists[1].complete(const WebDavResult.success([]));
      expect(await currentNavigation, isTrue);
      service.lists[0].complete(const WebDavResult.failure(_failed));
      expect(await oldNavigation, isFalse);
      expect(container.read(fileListProvider).currentPath, 'new-folder');

      final failedNavigation = files.navigateToFolder('missing');
      service.lists[2].complete(const WebDavResult.failure(_failed));
      expect(await failedNavigation, isFalse);
      expect(container.read(fileListProvider).currentPath, 'new-folder');
    },
  );
}
