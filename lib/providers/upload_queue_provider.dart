import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/upload_queue.dart';
import '../services/webdav_service.dart';
import '../services/transfer_history_retention.dart';
import '../services/webdav_exceptions.dart';
import '../screens/home_screen.dart' show selectedTabProvider;
import 'config_provider.dart';
import 'gotify_provider.dart';
import 'webdav_provider.dart';
import 'pending_upload_provider.dart';

/// Notifier for managing the upload queue.
class UploadQueueNotifier extends StateNotifier<UploadQueueState> {
  final WebDavService _service;
  final Ref _ref;
  bool _isRunning = false;
  DateTime? _lastProgressTime;
  int _lastUploadedBytes = 0;
  CancelToken? _cancelToken;
  int _nextItemId = 0;
  late final TransferHistoryRetention _historyRetention;

  UploadQueueNotifier(this._service, this._ref)
    : super(const UploadQueueState()) {
    _historyRetention = TransferHistoryRetention(
      canPrune: () => !state.isProcessing,
      onExpired: _removeCompleted,
    );
    addListener((next) {
      _historyRetention.update(
        next.items
            .where((item) => item.status == UploadStatus.completed)
            .map((item) => item.id),
      );
    }, fireImmediately: false);
  }

  void setAutoCleanupEnabled(bool enabled) {
    _historyRetention.setEnabled(enabled);
  }

  /// Add files to the upload queue.
  Future<void> addFiles(
    List<String> localPaths, {
    String? remoteBasePath,
  }) async {
    await _enqueueFiles(localPaths, remoteBasePath: remoteBasePath);
  }

  /// Automated uploads keep terminal failures in the queue for status queries.
  Future<String?> addAutomatedFile(
    String path, {
    required String remoteName,
  }) async {
    final ids = await _enqueueFiles(
      [path],
      remoteName: remoteName,
      automated: true,
    );
    return ids.firstOrNull;
  }

  Future<List<String>> _enqueueFiles(
    List<String> localPaths, {
    String? remoteBasePath,
    String? remoteName,
    bool automated = false,
  }) async {
    final newItems = <UploadItem>[];
    final serverId = automated
        ? _ref.read(activeFilesServerProvider)?.id
        : null;
    int addedSize = 0;

    for (final localPath in localPaths) {
      final file = File(localPath);
      if (await file.exists()) {
        final stat = await file.stat();
        final fileName = remoteName ?? p.basename(localPath);
        final remotePath = remoteBasePath != null
            ? '$remoteBasePath/$fileName'
            : '/RemoteSend/Files/$fileName';

        newItems.add(
          UploadItem(
            id: 'upload_${_nextItemId++}',
            localPath: localPath,
            remotePath: remotePath,
            fileName: fileName,
            fileSize: stat.size,
            automated: automated,
            serverId: serverId,
          ),
        );
        addedSize += stat.size;
      }
    }

    if (newItems.isNotEmpty) {
      state = state.copyWith(
        items: [...state.items, ...newItems],
        totalBytes: state.totalBytes + addedSize,
      );

      // Start processing if not already running
      if (!_isRunning) {
        _startProcessing();
      }
    }
    return newItems.map((item) => item.id).toList();
  }

  /// Add a folder to the upload queue (flattens all files).
  Future<void> addFolder(String localFolderPath) async {
    final folder = Directory(localFolderPath);
    if (!await folder.exists()) return;

    final folderName = p.basename(localFolderPath);
    final remoteBasePath = '/RemoteSend/Files/$folderName';
    final newItems = <UploadItem>[];
    int totalSize = state.totalBytes;

    // First, create the folder structure on the server
    await _service.createRemoteDirectory(remoteBasePath);

    // Collect all files recursively
    await for (final entity in folder.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        final relativePath = p
            .relative(entity.path, from: localFolderPath)
            .replaceAll('\\', '/');
        final fileName = p.basename(entity.path);
        final remotePath = '$remoteBasePath/$relativePath';

        // Ensure parent directory exists on server
        final parentDir = p.dirname(relativePath);
        if (parentDir.isNotEmpty && parentDir != '.') {
          await _service.createRemoteDirectory('$remoteBasePath/$parentDir');
        }

        newItems.add(
          UploadItem(
            id: 'upload_${_nextItemId++}',
            localPath: entity.path,
            remotePath: remotePath,
            fileName: fileName,
            fileSize: stat.size,
          ),
        );
        totalSize += stat.size;
      }
    }

    if (newItems.isNotEmpty) {
      state = state.copyWith(
        items: [...state.items, ...newItems],
        totalBytes: totalSize,
      );

      // Start processing if not already running
      if (!_isRunning) {
        _startProcessing();
      }
    }
  }

  /// Start processing the upload queue.
  void _startProcessing() {
    if (_isRunning) return;
    _cancelToken = null;
    _isRunning = true;
    _lastProgressTime = DateTime.now();
    _lastUploadedBytes = state.uploadedBytes;
    state = state.copyWith(isProcessing: true, startTime: DateTime.now());
    _processNext();
  }

  /// Process the next item in the queue.
  Future<void> _processNext() async {
    if (!mounted || !_isRunning) return;

    // Find the next pending item
    final pendingIndex = state.items.indexWhere(
      (i) => i.status == UploadStatus.pending,
    );
    if (pendingIndex == -1) {
      // No more items to process
      _isRunning = false;
      state = state.copyWith(isProcessing: false, currentSpeed: 0);
      // Refresh file list when done
      _ref.read(fileListProvider.notifier).refresh();
      return;
    }

    // Update item status to uploading
    final items = List<UploadItem>.from(state.items);
    items[pendingIndex] = items[pendingIndex].copyWith(
      status: UploadStatus.uploading,
    );
    state = state.copyWith(items: items);

    final item = items[pendingIndex];

    _cancelToken = CancelToken();

    final serverBeforeUpload = _ref.read(activeFilesServerProvider);
    final serverChanged =
        item.automated && serverBeforeUpload?.id != item.serverId;
    final result = serverChanged
        ? const WebDavResult<bool>.failure(
            WebDavConfigException(
              message: 'Files server changed before upload',
              userMessage: 'Files server changed before upload',
            ),
          )
        : await _service.uploadFileToPath(
            item.localPath,
            item.remotePath,
            cancelToken: _cancelToken,
            onProgress: (progress) {
              if (!mounted) return;

              // Calculate speed
              final now = DateTime.now();
              final itemUploadedBytes = (item.fileSize * progress).round();
              final totalUploaded = _calculateTotalUploaded(
                pendingIndex,
                itemUploadedBytes,
              );

              if (_lastProgressTime != null) {
                final elapsed = now
                    .difference(_lastProgressTime!)
                    .inMilliseconds;
                if (elapsed > 500) {
                  // Update speed every 500ms
                  final bytesUploaded = totalUploaded - _lastUploadedBytes;
                  final speed = bytesUploaded / (elapsed / 1000);
                  state = state.copyWith(currentSpeed: speed);
                  _lastProgressTime = now;
                  _lastUploadedBytes = totalUploaded;
                }
              }

              // Update item progress
              final updatedItems = List<UploadItem>.from(state.items);
              updatedItems[pendingIndex] = updatedItems[pendingIndex].copyWith(
                progress: progress,
              );
              state = state.copyWith(
                items: updatedItems,
                uploadedBytes: totalUploaded,
              );
            },
          );

    _cancelToken = null;

    if (!mounted || !_isRunning) return;

    // Update item status based on result
    final updatedItems = List<UploadItem>.from(state.items);
    final server = _ref.read(activeFilesServerProvider);
    final changedDuringUpload = item.automated && server?.id != item.serverId;
    if (result.isSuccess && !changedDuringUpload) {
      updatedItems[pendingIndex] = updatedItems[pendingIndex].copyWith(
        status: UploadStatus.completed,
        progress: 1.0,
      );
      if (server != null) {
        await _ref
            .read(gotifyProvider.notifier)
            .publishFileReady(
              server: server,
              remotePath: item.remotePath,
              fileName: item.fileName,
              fileSize: item.fileSize,
            );
        if (!mounted || !_isRunning) return;
      }
    } else {
      updatedItems[pendingIndex] = updatedItems[pendingIndex].copyWith(
        status: UploadStatus.failed,
        error: changedDuringUpload
            ? 'Files server changed during upload; remote result uncertain'
            : result.error?.userMessage,
      );

      // If the error is connection/auth/timeout-related,
      // move remaining files to pending upload page as fallback.
      if (!item.automated && _isConnectionError(result.error)) {
        final pendingPaths = <String>[];
        for (final item in updatedItems) {
          if (item.status == UploadStatus.pending && !item.automated) {
            pendingPaths.add(item.localPath);
          }
        }
        // Also include the failed item so user can retry it
        pendingPaths.add(item.localPath);

        if (pendingPaths.isNotEmpty) {
          _ref.read(pendingUploadProvider.notifier).addFiles(pendingPaths);
          // Switch to file depot tab so user sees the pending page
          _ref.read(selectedTabProvider.notifier).state = 1;
        }

        // Remove these items from the queue
        final remaining = updatedItems
            .where(
              (i) =>
                  i.status == UploadStatus.completed ||
                  (i.status == UploadStatus.failed && i.id != item.id) ||
                  (i.status == UploadStatus.pending && i.automated),
            )
            .toList();

        _isRunning = false;
        if (remaining.isEmpty) {
          state = state.clear();
        } else {
          state = state.copyWith(
            items: remaining,
            totalBytes: remaining.fold<int>(0, (sum, i) => sum + i.fileSize),
            uploadedBytes: remaining
                .where((i) => i.status == UploadStatus.completed)
                .fold<int>(0, (sum, i) => sum + i.fileSize),
            isProcessing: false,
            currentSpeed: 0,
          );
        }
        if (remaining.any((i) => i.status == UploadStatus.pending)) {
          _startProcessing();
        }
        return;
      }
    }
    state = state.copyWith(items: updatedItems);

    // Process next item
    _processNext();
  }

  /// Calculate total uploaded bytes including completed items.
  int _calculateTotalUploaded(int currentIndex, int currentItemUploaded) {
    int total = 0;
    for (int i = 0; i < state.items.length; i++) {
      if (i < currentIndex &&
          (state.items[i].status == UploadStatus.completed ||
              state.items[i].status == UploadStatus.failed)) {
        total += state.items[i].fileSize;
      } else if (i == currentIndex) {
        total += currentItemUploaded;
      }
    }
    return total;
  }

  /// Clear completed items from the queue.
  void clearCompleted() {
    if (state.isProcessing) return;
    _removeCompleted(
      state.items
          .where((item) => item.status == UploadStatus.completed)
          .map((item) => item.id)
          .toSet(),
    );
  }

  void _removeCompleted(Set<String> ids) {
    if (!mounted || state.isProcessing || ids.isEmpty) return;
    final remaining = state.items
        .where(
          (item) =>
              item.status != UploadStatus.completed || !ids.contains(item.id),
        )
        .toList();
    if (remaining.length == state.items.length) return;
    final total = remaining.fold<int>(0, (sum, item) => sum + item.fileSize);
    final removedBytes = state.items
        .where(
          (item) =>
              ids.contains(item.id) && item.status == UploadStatus.completed,
        )
        .fold<int>(0, (sum, item) => sum + item.fileSize);
    state = remaining.isEmpty
        ? state.clear()
        : state.copyWith(
            items: remaining,
            totalBytes: total,
            uploadedBytes: (state.uploadedBytes - removedBytes).clamp(0, total),
          );
    _lastUploadedBytes = state.uploadedBytes;
  }

  @override
  void dispose() {
    _historyRetention.dispose();
    super.dispose();
  }

  /// Clear all items from the queue (cancels current upload).
  void clearAll() {
    _cancelToken?.cancel();
    _isRunning = false;
    state = state.clear();
  }

  /// Retry failed items.
  void retryFailed() {
    final updatedItems = state.items.map((item) {
      if (item.status == UploadStatus.failed) {
        return item.copyWith(
          status: UploadStatus.pending,
          progress: 0,
          error: null,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);

    if (!_isRunning &&
        updatedItems.any((i) => i.status == UploadStatus.pending)) {
      _startProcessing();
    }
  }

  /// Check if an upload failure should fallback to pending page.
  /// Connection/auth/timeout/server errors all qualify.
  bool _isConnectionError(WebDavException? error) {
    if (error == null) return false;
    // NotFound means the remote folder doesn't exist — that's a
    // legitimate error we shouldn't fallback for.
    if (error is WebDavNotFoundException) return false;
    return true;
  }
}

/// Provider for upload queue state management (uses Files service).
final uploadQueueProvider =
    StateNotifierProvider<UploadQueueNotifier, UploadQueueState>((ref) {
      final service = ref.watch(webDavFilesServiceProvider);
      final notifier = UploadQueueNotifier(service, ref);
      notifier.setAutoCleanupEnabled(
        ref.read(autoClearTransferHistoryProvider),
      );
      ref.listen<bool>(autoClearTransferHistoryProvider, (_, enabled) {
        notifier.setAutoCleanupEnabled(enabled);
      });
      return notifier;
    });
