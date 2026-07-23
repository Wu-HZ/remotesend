import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/upload_queue.dart';
import '../services/webdav_service.dart';
import 'webdav_provider.dart';

/// Notifier for managing the upload queue.
class UploadQueueNotifier extends StateNotifier<UploadQueueState> {
  final WebDavService _service;
  final Ref _ref;
  bool _isRunning = false;
  DateTime? _lastProgressTime;
  int _lastUploadedBytes = 0;

  UploadQueueNotifier(this._service, this._ref) : super(const UploadQueueState());

  /// Add files to the upload queue.
  Future<void> addFiles(List<String> localPaths, {String? remoteBasePath}) async {
    final newItems = <UploadItem>[];
    int totalSize = state.totalBytes;

    for (final localPath in localPaths) {
      final file = File(localPath);
      if (await file.exists()) {
        final stat = await file.stat();
        final fileName = p.basename(localPath);
        final remotePath = remoteBasePath != null
            ? '$remoteBasePath/$fileName'
            : '/RemoteSend/Files/$fileName';

        newItems.add(UploadItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_${newItems.length}',
          localPath: localPath,
          remotePath: remotePath,
          fileName: fileName,
          fileSize: stat.size,
        ));
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
        final relativePath = p.relative(entity.path, from: localFolderPath).replaceAll('\\', '/');
        final fileName = p.basename(entity.path);
        final remotePath = '$remoteBasePath/$relativePath';

        // Ensure parent directory exists on server
        final parentDir = p.dirname(relativePath);
        if (parentDir.isNotEmpty && parentDir != '.') {
          await _service.createRemoteDirectory('$remoteBasePath/$parentDir');
        }

        newItems.add(UploadItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_${newItems.length}',
          localPath: entity.path,
          remotePath: remotePath,
          fileName: fileName,
          fileSize: stat.size,
        ));
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
    _isRunning = true;
    _lastProgressTime = DateTime.now();
    _lastUploadedBytes = state.uploadedBytes;
    state = state.copyWith(
      isProcessing: true,
      startTime: DateTime.now(),
    );
    _processNext();
  }

  /// Process the next item in the queue.
  Future<void> _processNext() async {
    if (!mounted || !_isRunning) return;

    // Find the next pending item
    final pendingIndex = state.items.indexWhere((i) => i.status == UploadStatus.pending);
    if (pendingIndex == -1) {
      // No more items to process
      _isRunning = false;
      state = state.copyWith(
        isProcessing: false,
        currentSpeed: 0,
      );
      // Refresh file list when done
      _ref.read(fileListProvider.notifier).refresh();
      return;
    }

    // Update item status to uploading
    final items = List<UploadItem>.from(state.items);
    items[pendingIndex] = items[pendingIndex].copyWith(status: UploadStatus.uploading);
    state = state.copyWith(items: items);

    final item = items[pendingIndex];

    // Upload the file
    final result = await _service.uploadFileToPath(
      item.localPath,
      item.remotePath,
      onProgress: (progress) {
        if (!mounted) return;

        // Calculate speed
        final now = DateTime.now();
        final itemUploadedBytes = (item.fileSize * progress).round();
        final totalUploaded = _calculateTotalUploaded(pendingIndex, itemUploadedBytes);

        if (_lastProgressTime != null) {
          final elapsed = now.difference(_lastProgressTime!).inMilliseconds;
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
        updatedItems[pendingIndex] = updatedItems[pendingIndex].copyWith(progress: progress);
        state = state.copyWith(
          items: updatedItems,
          uploadedBytes: totalUploaded,
        );
      },
    );

    if (!mounted) return;

    // Update item status based on result
    final updatedItems = List<UploadItem>.from(state.items);
    if (result.isSuccess) {
      updatedItems[pendingIndex] = updatedItems[pendingIndex].copyWith(
        status: UploadStatus.completed,
        progress: 1.0,
      );
    } else {
      updatedItems[pendingIndex] = updatedItems[pendingIndex].copyWith(
        status: UploadStatus.failed,
        error: result.error?.userMessage,
      );
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
    final remaining = state.items.where((i) => i.status != UploadStatus.completed).toList();
    final removedBytes = state.items
        .where((i) => i.status == UploadStatus.completed)
        .fold<int>(0, (sum, i) => sum + i.fileSize);

    state = state.copyWith(
      items: remaining,
      totalBytes: state.totalBytes - removedBytes,
      uploadedBytes: state.uploadedBytes - removedBytes,
    );

    if (remaining.isEmpty) {
      state = state.clear();
    }
  }

  /// Clear all items from the queue (cancels current upload).
  void clearAll() {
    _isRunning = false;
    state = state.clear();
  }

  /// Retry failed items.
  void retryFailed() {
    final updatedItems = state.items.map((item) {
      if (item.status == UploadStatus.failed) {
        return item.copyWith(status: UploadStatus.pending, progress: 0, error: null);
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);

    if (!_isRunning && updatedItems.any((i) => i.status == UploadStatus.pending)) {
      _startProcessing();
    }
  }
}

/// Provider for upload queue state management (uses Files service).
final uploadQueueProvider =
    StateNotifierProvider<UploadQueueNotifier, UploadQueueState>((ref) {
  final service = ref.watch(webDavFilesServiceProvider);
  return UploadQueueNotifier(service, ref);
});
