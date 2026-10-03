import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/providers/app_visibility_provider.dart';
import 'package:remote_send/providers/camera_capture_provider.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/download_cache_provider.dart';
import 'package:remote_send/providers/download_path_provider.dart';
import 'package:remote_send/providers/download_state_provider.dart';
import 'package:remote_send/providers/gotify_coordinator_provider.dart';
import 'package:remote_send/providers/gotify_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/screens/file_depot_screen.dart';
import 'package:remote_send/screens/settings_screen.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/download_path_service.dart';
import 'package:remote_send/services/webdav_exceptions.dart';
import 'package:remote_send/services/webdav_service.dart';

class _Config extends ConfigNotifier {
  _Config(AppConfig config) : super(ConfigService()) {
    state = AsyncData(config);
  }
  void select(String id) {
    state = AsyncData(state.requireValue.copyWith(activeFilesServerId: id));
  }
}

class _Source extends WebDavService {
  final String id;
  _Source(this.id);
  @override
  Future<WebDavResult<bool>> downloadFile(
    String remoteName,
    String localPath, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await File(localPath).writeAsString(id * 3);
    onProgress?.call(3, 3);
    return const WebDavResult.success(true);
  }

  @override
  Future<WebDavResult<int>> downloadFolder(
    String remoteFolderName,
    String localFolderPath, {
    void Function(List<RemoteFileInfo>)? onFilesCollected,
    void Function(String, int, int, int, int)? onProgress,
  }) async {
    final relative = p.join('nested', 'report.txt');
    final file = File(p.join(localFolderPath, relative));
    await file.parent.create(recursive: true);
    onFilesCollected?.call([
      RemoteFileInfo(
        remotePath: '$remoteFolderName/nested/report.txt',
        relativePath: relative,
        fileName: 'report.txt',
        fileSize: 3,
      ),
    ]);
    await file.writeAsString(id * 3);
    onProgress?.call('report.txt', 1, 1, 3, 3);
    return const WebDavResult.success(1);
  }
}

class _Files extends FileListNotifier {
  _Files(RemoteFile file) : super(_Source('unused')) {
    state = FileListState(files: [file]);
  }
  @override
  Future<bool> refresh({
    bool retryTransient = true,
    Duration retryDelay = const Duration(seconds: 1),
  }) async => true;
}

class _Connection extends ConnectionNotifier {
  _Connection() : super(_Source('unused')) {
    state = const ConnectionStatus(state: WebDavConnectionState.connected);
  }
}

class _Paths extends DownloadPathService {
  _Paths(Directory root) : super(defaultDirectory: () async => root);
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<String> downloadPath({
    required String configuredDirectory,
    required ServerConfig server,
    required String fileName,
    bool isDirectory = false,
  }) async {
    if (!started.isCompleted) started.complete();
    if (gate != null) await gate!.future;
    return super.downloadPath(
      configuredDirectory: configuredDirectory,
      server: server,
      fileName: fileName,
      isDirectory: isDirectory,
    );
  }
}

class _Gotify extends Fake implements GotifyNotifier {
  final controller = StreamController<RemoteSendEvent>.broadcast();
  @override
  Stream<RemoteSendEvent> get events => controller.stream;
  @override
  bool isDeferredEvent(String id) => false;
  @override
  Future<void> acknowledgeEvent(String id) async {}
  @override
  Future<bool> publishFileReceived(RemoteSendEvent source) async => true;
  @override
  void replayPendingEvents() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Paths paths;
  late ProviderContainer container;
  late _Config config;
  final opened = <String>[];
  final sources = <String>[];
  final a = ServerConfig(
    id: 'a',
    name: '同名服务器',
    serverUrl: 'https://example.invalid/a',
    username: 'u',
    password: 'p',
    createdAt: DateTime(2026),
  );
  final b = a.copyWith(id: 'b', serverUrl: 'https://example.invalid/b');
  const file = RemoteFile(
    name: 'report.txt',
    path: '/RemoteSend/Files/report.txt',
    size: 3,
    isDirectory: false,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('download_workflow_');
    paths = _Paths(root);
    opened.clear();
    sources.clear();
    config = _Config(
      AppConfig(
        servers: [a, b],
        activeFilesServerId: 'a',
        downloadLocation: root.path,
        gotify: GotifyConfig(autoDownloadEnabled: true),
      ),
    );
    container = ProviderContainer(
      overrides: [
        configProvider.overrideWith((ref) => config),
        cameraSupportedProvider.overrideWithValue(false),
        downloadPathServiceProvider.overrideWithValue(paths),
        downloadSourceServiceProvider.overrideWithValue((server) {
          sources.add(server.id);
          return _Source(server.id);
        }),
        openLocalDirectoryProvider.overrideWithValue((path) async {
          opened.add(path);
          return true;
        }),
        fileListProvider.overrideWith((ref) => _Files(file)),
        filesConnectionStatusProvider.overrideWith((ref) => _Connection()),
      ],
    );
    await container.read(downloadCacheProvider.notifier).ready;
  });
  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, bool Function() complete) async {
    for (var i = 0; !complete() && i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(complete(), isTrue);
  }

  testWidgets('顶部打开当前服务器子目录', (tester) async {
    await show(tester, const FileDepotScreen());
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('打开下载文件夹'));
      // 等待目录分配和系统打开回调，不实际启动文件管理器。
      for (var i = 0; opened.isEmpty && i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(opened, [
      await tester.runAsync(
        () => paths.serverDirectory(configuredDirectory: root.path, server: a),
      ),
    ]);
    expect(p.dirname(opened.single), root.path);
  });

  testWidgets('旧缓存的打开操作仍定位到旧根目录', (tester) async {
    final old = File(p.join(root.path, file.name));
    await tester.runAsync(() async {
      await old.writeAsString('old');
      await container
          .read(downloadCacheProvider.notifier)
          .markDownloaded(serverId: 'a', file: file, localPath: old.path);
    });
    await show(tester, const FileDepotScreen());
    await tester.tap(find.text('report.txt'));
    await waitFor(tester, () => find.text('打开文件夹').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开文件夹'));
    await tester.pumpAndSettle();
    expect(opened, [root.path]);
    expect(sources, ['a']);
    expect(await tester.runAsync(old.readAsString), 'old');
  });

  testWidgets('等待目录时切换服务器，下载来源和目标仍属于原服务器', (tester) async {
    paths.gate = Completer<void>();
    final finished = Completer<void>();
    final subscription = container.listen(downloadCacheProvider, (_, next) {
      if (next.entries.containsKey('a::${file.path}') &&
          !finished.isCompleted) {
        finished.complete();
      }
    });
    addTearDown(subscription.close);
    await show(tester, const FileDepotScreen());
    await tester.tap(find.text('report.txt'));
    await waitFor(tester, () => paths.started.isCompleted);
    config.select('b');
    paths.gate!.complete();
    await waitFor(tester, () => finished.isCompleted);
    final saved = container
        .read(downloadCacheProvider)
        .localPathFor(serverId: 'a', file: file)!;
    expect(sources, ['a']);
    expect(await tester.runAsync(() => File(saved).readAsString()), 'aaa');
    expect(
      p.dirname(saved),
      await tester.runAsync(
        () => paths.serverDirectory(configuredDirectory: root.path, server: a),
      ),
    );
    expect(
      container
          .read(downloadCacheProvider)
          .localPathFor(serverId: 'b', file: file),
      isNull,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开文件夹'));
    await tester.pump();
    expect(opened, [p.dirname(saved)]);
  });

  testWidgets('设置页只显示总下载位置，不显示额外分目录说明', (tester) async {
    await show(tester, const SettingsScreen());
    await tester.scrollUntilVisible(
      find.text(root.path),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(root.path), findsOneWidget);
    expect(find.text('新下载的文件将按服务器分别保存到子文件夹，已有文件保持原位。'), findsNothing);
  });

  test('整文件夹下载使用固定来源服务并保留内部层级', () async {
    final directory = await paths.downloadPath(
      configuredDirectory: root.path,
      server: b,
      fileName: 'docs',
      isDirectory: true,
    );
    final notifier = DownloadStateNotifier(_Source('a'));
    addTearDown(notifier.dispose);
    final result = await notifier.downloadFolder(
      remoteFolderName: 'docs',
      localFolderPath: directory,
      serviceOverride: _Source('b'),
    );
    expect(result.isSuccess, isTrue);
    expect(
      await File(p.join(directory, 'nested', 'report.txt')).readAsString(),
      'bbb',
    );
    expect(
      notifier.state.items.single.localPath,
      p.join(directory, 'nested', 'report.txt'),
    );
  });

  test('Gotify 非当前服务器自动下载与手动下载使用同一目录规则', () async {
    const statusChannel = MethodChannel(
      'dev.fluttercommunity.plus/connectivity_status',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statusChannel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(statusChannel, null),
    );
    final gotify = _Gotify();
    addTearDown(gotify.controller.close);
    final coordinatorProvider =
        StateNotifierProvider<
          GotifyCoordinatorNotifier,
          GotifyCoordinatorState
        >((ref) => GotifyCoordinatorNotifier(gotify, ref));
    final finished = Completer<void>();
    final subscription = container.listen(coordinatorProvider, (_, next) {
      if (next.lastReceivedFile != null && !finished.isCompleted) {
        finished.complete();
      }
    });
    addTearDown(subscription.close);
    container.read(appForegroundProvider.notifier).state = true;
    gotify.controller.add(
      RemoteSendEvent(
        type: RemoteSendEvent.fileReady,
        senderDeviceId: 'other',
        senderName: 'test',
        payload: {
          'serverKey': webDavServerKey(b),
          'fileName': file.name,
          'remotePath': file.path,
          'fileSize': 3,
        },
      ),
    );
    await finished.future.timeout(const Duration(seconds: 5));
    final saved = container
        .read(downloadCacheProvider)
        .localPathFor(serverId: 'b', file: file)!;
    expect(sources, ['b']);
    expect(
      p.dirname(saved),
      await paths.serverDirectory(configuredDirectory: root.path, server: b),
    );
    expect(await File(saved).readAsString(), 'bbb');
    expect(container.read(activeFilesServerProvider)?.id, 'a');
  });
}
