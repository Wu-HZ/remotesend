import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/providers/download_cache_provider.dart';
import 'package:remote_send/services/download_path_service.dart';
import 'package:remote_send/services/webdav_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'download cache uses ETag as the authoritative remote version',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'remote_send_cache_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final localFile = File('${directory.path}/report.txt');
      await localFile.writeAsString('data');
      final cachedFile = RemoteFile(
        name: 'report.txt',
        path: '/RemoteSend/Files/report.txt',
        size: 4,
        modifiedTime: DateTime.utc(2026, 1, 1),
        eTag: '"version-1"',
        isDirectory: false,
      );
      final cache = DownloadCacheState(
        entries: {
          DownloadCacheState.keyFor('server', cachedFile): DownloadCacheEntry(
            localPath: localFile.path,
            isDirectory: false,
            remoteSize: 4,
            remoteModifiedTime: cachedFile.modifiedTime,
            remoteETag: cachedFile.eTag,
          ),
        },
      );

      final unchanged = RemoteFile(
        name: cachedFile.name,
        path: cachedFile.path,
        size: cachedFile.size,
        modifiedTime: DateTime.utc(2026, 1, 2),
        eTag: cachedFile.eTag,
        isDirectory: false,
      );
      final updated = RemoteFile(
        name: cachedFile.name,
        path: cachedFile.path,
        size: cachedFile.size,
        modifiedTime: cachedFile.modifiedTime,
        eTag: '"version-2"',
        isDirectory: false,
      );

      expect(cache.isDownloaded(serverId: 'server', file: unchanged), isTrue);
      expect(cache.isDownloaded(serverId: 'server', file: updated), isFalse);
    },
  );

  test(
    'download cache falls back to modification time without ETags',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'remote_send_cache_mtime_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final localFile = File('${directory.path}/report.txt');
      await localFile.writeAsString('data');
      final originalTime = DateTime.utc(2026, 1, 1);
      const remotePath = '/RemoteSend/Files/report.txt';
      final cachedFile = RemoteFile(
        name: 'report.txt',
        path: remotePath,
        size: 4,
        modifiedTime: originalTime,
        isDirectory: false,
      );
      final cache = DownloadCacheState(
        entries: {
          DownloadCacheState.keyFor('server', cachedFile): DownloadCacheEntry(
            localPath: localFile.path,
            isDirectory: false,
            remoteSize: 4,
            remoteModifiedTime: originalTime,
          ),
        },
      );
      final updated = RemoteFile(
        name: 'report.txt',
        path: remotePath,
        size: 4,
        modifiedTime: originalTime.add(const Duration(seconds: 1)),
        isDirectory: false,
      );

      expect(cache.isDownloaded(serverId: 'server', file: updated), isFalse);
    },
  );

  test(
    'persisted download cache can be awaited before the first click',
    () async {
      final entry = DownloadCacheEntry(
        localPath: 'C:/Downloads/report.txt',
        isDirectory: false,
        remoteSize: 4,
        remoteModifiedTime: DateTime.utc(2026, 1, 1),
        remoteETag: '"version-1"',
      );
      SharedPreferences.setMockInitialValues({
        'download_cache': jsonEncode({
          'server::/RemoteSend/Files/report.txt': entry.toJson(),
        }),
      });
      final notifier = DownloadCacheNotifier();
      addTearDown(notifier.dispose);

      await notifier.ready;

      expect(notifier.state.entries, hasLength(1));
      expect(
        notifier
            .state
            .entries['server::/RemoteSend/Files/report.txt']
            ?.remoteETag,
        '"version-1"',
      );
    },
  );

  test('启用服务器子目录后旧缓存仍引用原文件，不搬动或重下', () async {
    final directory = await Directory.systemTemp.createTemp('legacy_download_');
    addTearDown(() => directory.delete(recursive: true));
    final old = File('${directory.path}/report.txt');
    await old.writeAsString('old');
    final remote = RemoteFile(
      name: 'report.txt',
      path: '/RemoteSend/Files/report.txt',
      size: 3,
      isDirectory: false,
    );
    final entry = DownloadCacheEntry(
      localPath: old.path,
      isDirectory: false,
      remoteSize: 3,
    );
    SharedPreferences.setMockInitialValues({
      'download_cache': jsonEncode({'a::${remote.path}': entry.toJson()}),
    });
    final notifier = DownloadCacheNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;
    final server = ServerConfig(
      id: 'a',
      name: '服务器',
      serverUrl: 'https://example.invalid',
      username: 'test',
      password: 'test',
      createdAt: DateTime(2026),
    );
    await DownloadPathService().serverDirectory(
      configuredDirectory: directory.path,
      server: server,
    );
    expect(notifier.state.localPathFor(serverId: 'a', file: remote), old.path);
    expect(await old.readAsString(), 'old');
    expect(notifier.state.localPathFor(serverId: 'b', file: remote), isNull);
  });

  test('不同服务器的同一路径缓存分别保留真实本地路径', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'isolated_download_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final notifier = DownloadCacheNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;
    final paths = DownloadPathService();
    final remote = RemoteFile(
      name: 'report.txt',
      path: '/RemoteSend/Files/report.txt',
      size: 3,
      isDirectory: false,
    );
    final saved = <String, String>{};
    for (final id in ['a', 'b']) {
      final server = ServerConfig(
        id: id,
        name: '服务器',
        serverUrl: 'https://example.invalid',
        username: 'test',
        password: 'test',
        createdAt: DateTime(2026),
      );
      final path = await paths.downloadPath(
        configuredDirectory: directory.path,
        server: server,
        fileName: remote.name,
      );
      await File(path).writeAsString(id * 3);
      await notifier.markDownloaded(
        serverId: id,
        file: remote,
        localPath: path,
      );
      saved[id] = path;
    }
    expect(saved['a'], isNot(saved['b']));
    expect(
      notifier.state.localPathFor(serverId: 'a', file: remote),
      saved['a'],
    );
    expect(
      notifier.state.localPathFor(serverId: 'b', file: remote),
      saved['b'],
    );
  });

  test('available download path never overwrites an existing file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'remote_send_path_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final original = File('${directory.path}/report.txt');
    final firstCopy = File('${directory.path}/report (1).txt');
    await original.writeAsString('old');
    await firstCopy.writeAsString('older');

    final available = await availableDownloadPath(original.path);

    expect(
      available,
      '${directory.path}${Platform.pathSeparator}report (2).txt',
    );
    expect(await original.readAsString(), 'old');
    expect(await firstCopy.readAsString(), 'older');
  });
}
