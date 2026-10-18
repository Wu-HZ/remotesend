import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/download_queue.dart';
import 'package:remote_send/models/upload_queue.dart';
import 'package:remote_send/providers/download_state_provider.dart';
import 'package:remote_send/providers/upload_queue_provider.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/services/webdav_exceptions.dart';
import 'package:remote_send/services/webdav_service.dart';

enum _Stage { pending, active, completed, failed }

class _Record {
  const _Record(this.id, this.stage);
  final String id;
  final _Stage stage;
  double get progress => switch (stage) {
    _Stage.completed => 1,
    _Stage.failed => 0.4,
    _Stage.active => 0.5,
    _Stage.pending => 0,
  };
}

class _UnusedRef extends Fake implements Ref {}

class _Uploads extends UploadQueueNotifier {
  _Uploads([WebDavService? service, Ref? ref])
    : super(service ?? WebDavService(), ref ?? _UnusedRef());
  void seed(UploadQueueState next) => state = next;
}

class _Downloads extends DownloadStateNotifier {
  _Downloads() : super(WebDavService());
  void seed(DownloadState next) => state = next;
}

class _Queues {
  final uploads = _Uploads();
  final downloads = _Downloads();

  void seed(List<_Record> records, {bool busy = false}) {
    final total = records.length * 10;
    final transferred = records.fold<int>(
      0,
      (sum, r) => sum + (10 * r.progress).round(),
    );
    uploads.seed(
      UploadQueueState(
        isProcessing: busy,
        totalBytes: total,
        uploadedBytes: transferred,
        items: records
            .map(
              (r) => UploadItem(
                id: r.id,
                localPath: '/local/${r.id}',
                remotePath: '/remote/${r.id}',
                fileName: r.id,
                fileSize: 10,
                progress: r.progress,
                status: switch (r.stage) {
                  _Stage.pending => UploadStatus.pending,
                  _Stage.active => UploadStatus.uploading,
                  _Stage.completed => UploadStatus.completed,
                  _Stage.failed => UploadStatus.failed,
                },
              ),
            )
            .toList(),
      ),
    );
    downloads.seed(
      DownloadState(
        isDownloading: busy,
        totalFiles: records.length,
        totalBytes: total,
        downloadedBytes: transferred,
        progress: total > 0 ? transferred / total : 0,
        fileName: records.isEmpty ? null : records.last.id,
        error: records.any((r) => r.stage == _Stage.failed) ? 'failed' : null,
        items: records
            .map(
              (r) => DownloadItem(
                id: r.id,
                localPath: '/local/${r.id}',
                remotePath: '/remote/${r.id}',
                fileName: r.id,
                fileSize: 10,
                progress: r.progress,
                status: switch (r.stage) {
                  _Stage.pending => DownloadStatus.pending,
                  _Stage.active => DownloadStatus.downloading,
                  _Stage.completed => DownloadStatus.completed,
                  _Stage.failed => DownloadStatus.failed,
                },
              ),
            )
            .toList(),
      ),
    );
  }

  void expectIds(List<String> expected) {
    expect(uploads.state.items.map((i) => i.id), expected);
    expect(downloads.state.items.map((i) => i.id), expected);
  }

  void dispose() {
    uploads.dispose();
    downloads.dispose();
  }
}

class _Source extends WebDavService {
  final calls = <String>[];
  Completer<WebDavResult<int>>? folderGate;

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
  Future<WebDavResult<bool>> downloadFile(
    String remoteName,
    String localPath, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    calls.add(remoteName);
    onProgress?.call(10, 10);
    if (remoteName == 'failed') {
      return const WebDavResult.failure(
        WebDavNotFoundException(message: 'Missing'),
      );
    }
    return const WebDavResult.success(true);
  }

  @override
  Future<WebDavResult<int>> downloadFolder(
    String remoteFolderName,
    String localFolderPath, {
    void Function(List<RemoteFileInfo>)? onFilesCollected,
    void Function(String, int, int, int, int)? onProgress,
  }) {
    onFilesCollected?.call([
      for (final name in ['first', 'second'])
        RemoteFileInfo(
          remotePath: '$remoteFolderName/$name',
          relativePath: name,
          fileName: name,
          fileSize: 10,
        ),
    ]);
    onProgress?.call('first', 1, 2, 10, 10);
    onProgress?.call('second', 2, 2, 1, 10);
    return folderGate!.future;
  }
}

class _Files extends FileListNotifier {
  _Files() : super(WebDavService());

  @override
  Future<bool> refresh({
    bool retryTransient = true,
    Duration retryDelay = const Duration(seconds: 1),
  }) async => true;
}

void main() {
  void queueTest(
    String name,
    Future<void> Function(WidgetTester, _Queues) body,
  ) {
    testWidgets(name, (tester) async {
      final queues = _Queues();
      try {
        await body(tester, queues);
      } finally {
        queues.dispose();
      }
    });
  }

  queueTest(
    'successful upload and download records expire and reset summary state',
    (tester, q) async {
      q.seed([const _Record('done', _Stage.completed)]);
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      q.expectIds(['done']);
      await tester.pump(const Duration(seconds: 1));
      q.expectIds([]);
      expect(q.uploads.state.totalBytes, 0);
      expect(q.uploads.state.uploadedBytes, 0);
      expect(q.uploads.state.statusText, 'Idle');
      expect(q.downloads.state.totalBytes, 0);
      expect(q.downloads.state.downloadedBytes, 0);
      expect(q.downloads.state.totalFiles, 0);
      expect(q.downloads.state.fileName, isNull);
      expect(q.downloads.state.statusText, 'Idle');
    },
  );

  queueTest(
    'failed and pending records survive while completed bytes are removed',
    (tester, q) async {
      q.seed([
        const _Record('done', _Stage.completed),
        const _Record('failed', _Stage.failed),
        const _Record('pending', _Stage.pending),
      ]);
      await tester.pump(const Duration(minutes: 5));
      q.expectIds(['failed', 'pending']);
      expect(q.uploads.state.totalBytes, 20);
      expect(q.uploads.state.uploadedBytes, 4);
      expect(q.downloads.state.totalBytes, 20);
      expect(q.downloads.state.downloadedBytes, 4);
      expect(q.downloads.state.totalFiles, 2);
      expect(q.downloads.state.statusText, 'Failed');
      await tester.pump(const Duration(hours: 1));
      q.expectIds(['failed', 'pending']);
    },
  );

  queueTest('each completion keeps its own five-minute deadline', (
    tester,
    q,
  ) async {
    q.seed([const _Record('old', _Stage.completed)]);
    await tester.pump(const Duration(minutes: 1));
    q.seed([
      const _Record('old', _Stage.completed),
      const _Record('new', _Stage.completed),
    ]);
    await tester.pump(const Duration(minutes: 4));
    q.expectIds(['new']);
    expect(q.uploads.state.totalBytes, 10);
    expect(q.downloads.state.totalFiles, 1);
    await tester.pump(const Duration(minutes: 1));
    q.expectIds([]);
  });

  queueTest(
    'cleanup waits for active transfers then removes only expired success records',
    (tester, q) async {
      q.seed([
        const _Record('old', _Stage.completed),
        const _Record('active', _Stage.active),
        const _Record('pending', _Stage.pending),
      ], busy: true);
      await tester.pump(const Duration(minutes: 6));
      q.expectIds(['old', 'active', 'pending']);
      expect(q.uploads.state.isProcessing, isTrue);
      expect(q.downloads.state.isDownloading, isTrue);
      q.seed([
        const _Record('old', _Stage.completed),
        const _Record('active', _Stage.completed),
        const _Record('pending', _Stage.failed),
      ]);
      await tester.pump();
      q.expectIds(['active', 'pending']);
      await tester.pump(const Duration(minutes: 5));
      q.expectIds(['pending']);
    },
  );

  queueTest(
    'manual clearing cancels old cleanup and does not erase new records',
    (tester, q) async {
      q.seed([const _Record('old', _Stage.completed)]);
      await tester.pump(const Duration(minutes: 4));
      q.uploads.clearAll();
      q.downloads.clearAll();
      q.seed([const _Record('new', _Stage.completed)]);
      await tester.pump(const Duration(minutes: 1));
      q.expectIds(['new']);
      await tester.pump(const Duration(minutes: 4));
      q.expectIds([]);
    },
  );

  queueTest(
    'failed tasks get a fresh retention period after a successful retry',
    (tester, q) async {
      q.seed([const _Record('retry', _Stage.failed)]);
      await tester.pump(const Duration(minutes: 10));
      q.expectIds(['retry']);
      q.seed([const _Record('retry', _Stage.completed)]);
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      q.expectIds(['retry']);
      await tester.pump(const Duration(seconds: 1));
      q.expectIds([]);
    },
  );

  testWidgets(
    'real upload completion schedules cleanup without opening the queue page',
    (tester) async {
      final provider = StateNotifierProvider<_Uploads, UploadQueueState>(
        (ref) => _Uploads(_Source(), ref),
      );
      final container = ProviderContainer(
        overrides: [
          activeFilesServerProvider.overrideWithValue(null),
          fileListProvider.overrideWith((ref) => _Files()),
        ],
      );
      try {
        final notifier = container.read(provider.notifier);
        notifier.seed(
          const UploadQueueState(
            totalBytes: 10,
            items: [
              UploadItem(
                id: 'pending',
                localPath: '/local',
                remotePath: '/remote',
                fileName: 'file',
                fileSize: 10,
              ),
            ],
          ),
        );
        notifier.retryFailed();
        await tester.pump();
        expect(notifier.state.items.single.status, UploadStatus.completed);
        await tester.pump(const Duration(minutes: 5));
        expect(notifier.state.items, isEmpty);
        expect(notifier.state.statusText, 'Idle');
      } finally {
        container.dispose();
      }
    },
  );

  testWidgets(
    'real download completion schedules cleanup and rapid tasks have unique ids',
    (tester) async {
      final source = _Source();
      final notifier = DownloadStateNotifier(source);
      try {
        final first = notifier.downloadFile(
          remoteName: 'first',
          localPath: '/first',
          fileSize: 10,
        );
        final second = notifier.downloadFile(
          remoteName: 'second',
          localPath: '/second',
          fileSize: 10,
        );
        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(source.calls, ['first', 'second']);
        expect(notifier.state.items.map((i) => i.id).toSet(), hasLength(2));
        await tester.pump(const Duration(minutes: 5));
        expect(notifier.state.items, isEmpty);
      } finally {
        notifier.dispose();
      }
    },
  );

  testWidgets(
    'a real failed download is retained and does not expire with successful tasks',
    (tester) async {
      final notifier = DownloadStateNotifier(_Source());
      try {
        await notifier.downloadFile(
          remoteName: 'success',
          localPath: '/success',
          fileSize: 10,
        );
        await notifier.downloadFile(
          remoteName: 'failed',
          localPath: '/failed',
          fileSize: 10,
        );
        await tester.pump(const Duration(minutes: 10));
        expect(notifier.state.items, hasLength(1));
        expect(notifier.state.items.single.status, DownloadStatus.failed);
        expect(notifier.state.statusText, 'Failed');
      } finally {
        notifier.dispose();
      }
    },
  );

  testWidgets(
    'folder download indices stay stable until the transfer finishes',
    (tester) async {
      final source = _Source()..folderGate = Completer<WebDavResult<int>>();
      final notifier = DownloadStateNotifier(source);
      try {
        final download = notifier.downloadFolder(
          remoteFolderName: 'docs',
          localFolderPath: '/docs',
        );
        expect(notifier.state.items.first.status, DownloadStatus.completed);
        await tester.pump(const Duration(minutes: 5));
        expect(notifier.state.items, hasLength(2));
        source.folderGate!.complete(const WebDavResult.success(2));
        await download;
        await tester.pump();
        expect(notifier.state.items, hasLength(1));
        expect(notifier.state.items.single.fileName, 'second');
        expect(notifier.state.items.single.status, DownloadStatus.completed);
        await tester.pump(const Duration(minutes: 5));
        expect(notifier.state.items, isEmpty);
      } finally {
        notifier.dispose();
      }
    },
  );
}
