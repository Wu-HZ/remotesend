import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/download_path_provider.dart';
import 'package:remote_send/providers/download_state_provider.dart';
import 'package:remote_send/providers/upload_queue_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/screens/transfer_queue_screen.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/download_path_service.dart';
import 'package:remote_send/services/webdav_exceptions.dart';
import 'package:remote_send/services/webdav_service.dart';

const _toggle = ValueKey('transfer-history-auto-cleanup-toggle');

class _ConfigStore extends ConfigService {
  _ConfigStore({bool enabled = true})
    : stored = AppConfig(autoClearTransferHistory: enabled);
  AppConfig stored;
  bool failSaves = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppConfig> loadConfig() async => stored;

  @override
  Future<bool> saveConfig(AppConfig config) async {
    if (failSaves) return false;
    stored = AppConfig.fromJsonString(config.toJsonString());
    return true;
  }
}

class _Paths extends DownloadPathService {
  @override
  Future<String> rootPath(String configuredDirectory) async => '/downloads';
}

class _Source extends WebDavService {
  @override
  Future<WebDavResult<bool>> downloadFile(
    String remoteName,
    String localPath, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress?.call(5, 5);
    return const WebDavResult.success(true);
  }

  @override
  Future<WebDavResult<bool>> uploadFileToPath(
    String localPath,
    String remotePath, {
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress?.call(1);
    return const WebDavResult.success(true);
  }

  @override
  Future<WebDavResult<List<RemoteFile>>> listFiles([String? subPath]) async =>
      const WebDavResult.success([]);
}

class _Harness {
  _Harness(this.store) {
    container = ProviderContainer(
      overrides: [
        configServiceProvider.overrideWithValue(store),
        webDavFilesServiceProvider.overrideWithValue(_Source()),
        downloadPathServiceProvider.overrideWithValue(_Paths()),
      ],
    );
  }
  final _ConfigStore store;
  late final ProviderContainer container;

  Future<void> mount(WidgetTester tester) async {
    await container.read(configProvider.notifier).initialize();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TransferQueueScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(_toggle)).value;

  Future<void> download() => container
      .read(downloadStateProvider.notifier)
      .downloadFile(
        remoteName: 'report.txt',
        localPath: '/report.txt',
        fileSize: 5,
      );
}

void main() {
  testWidgets(
    'switch is visible on an empty queue, defaults on and survives restart',
    (tester) async {
      final store = _ConfigStore();
      var harness = _Harness(store);
      try {
        await harness.mount(tester);
        expect(harness.enabled(tester), isTrue);
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(harness.enabled(tester), isFalse);
        expect(store.stored.autoClearTransferHistory, isFalse);
        await tester.pumpWidget(const SizedBox());
        harness.container.dispose();
        harness = _Harness(store);
        await harness.mount(tester);
        expect(harness.enabled(tester), isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox());
        harness.container.dispose();
      }
    },
  );

  testWidgets(
    'disabling cancels pending cleanup and re-enabling starts five fresh minutes',
    (tester) async {
      final h = _Harness(_ConfigStore());
      try {
        await h.mount(tester);
        await h.download();
        final notifier = h.container.read(downloadStateProvider.notifier);
        await tester.pump(const Duration(minutes: 4));
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(minutes: 10));
        expect(notifier.state.items, hasLength(1));
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(
          h.container.read(downloadStateProvider.notifier),
          same(notifier),
        );
        await tester.pump(const Duration(minutes: 4, seconds: 59));
        expect(notifier.state.items, hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        expect(notifier.state.items, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        h.container.dispose();
      }
    },
  );

  testWidgets(
    'saved disabled preference applies to uploads and downloads before opening the page',
    (tester) async {
      final h = _Harness(_ConfigStore(enabled: false));
      Directory? root;
      try {
        await h.container.read(configProvider.notifier).initialize();
        await h.download();
        final uploads = h.container.read(uploadQueueProvider.notifier);
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('cleanup_toggle_');
          final file = await File(
            '${root!.path}/upload.txt',
          ).writeAsString('hello');
          await uploads.addFiles([file.path]);
        });
        await tester.pump();
        expect(uploads.state.completedCount, 1);
        final downloads = h.container.read(downloadStateProvider.notifier);
        await tester.pump(const Duration(minutes: 6));
        expect(uploads.state.items, hasLength(1));
        expect(downloads.state.items, hasLength(1));
        await h.mount(tester);
        expect(h.enabled(tester), isFalse);
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(h.container.read(uploadQueueProvider.notifier), same(uploads));
        await tester.pump(const Duration(minutes: 5));
        expect(uploads.state.items, isEmpty);
        expect(downloads.state.items, isEmpty);
        expect(File('${root!.path}/upload.txt').existsSync(), isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        h.container.dispose();
        if (root != null) {
          await tester.runAsync(() => root!.delete(recursive: true));
        }
      }
    },
  );

  testWidgets(
    'failed saves restore the previous switch value and show an error',
    (tester) async {
      final store = _ConfigStore()..failSaves = true;
      final h = _Harness(store);
      try {
        await h.mount(tester);
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(h.enabled(tester), isTrue);
        expect(store.stored.autoClearTransferHistory, isTrue);
        expect(find.text('Failed to save'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        h.container.dispose();
      }
    },
  );

  testWidgets('cleanup switch fits a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    final h = _Harness(_ConfigStore());
    try {
      await h.mount(tester);
      expect(find.byKey(_toggle), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      h.container.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
}
