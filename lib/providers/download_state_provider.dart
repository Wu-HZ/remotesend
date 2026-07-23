import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/download_queue.dart';
import '../services/webdav_service.dart';
import '../services/webdav_exceptions.dart';
import 'webdav_provider.dart';

/// State for tracking current download.
class DownloadState {
  final bool isDownloading;
  final String? fileName;
  final double progress;
  final int currentFileIndex;
  final int totalFiles;
  final String? error;
  final DateTime? startTime;
  final double currentSpeed; // bytes per second
  final int totalBytes;
  final int downloadedBytes;
  final List<DownloadItem> items;

  const DownloadState({
    this.isDownloading = false,
    this.fileName,
    this.progress = 0,
    this.currentFileIndex = 0,
    this.totalFiles = 0,
    this.error,
    this.startTime,
    this.currentSpeed = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.items = const [],
  });

  bool get isFolderDownload => totalFiles > 1;

  int get pendingCount => items.where((i) => i.status == DownloadStatus.pending).length;

  int get completedCount => items.where((i) => i.status == DownloadStatus.completed).length;

  int get failedCount => items.where((i) => i.status == DownloadStatus.failed).length;

  DownloadItem? get currentItem => items.cast<DownloadItem?>().firstWhere(
        (i) => i?.status == DownloadStatus.downloading,
        orElse: () => null,
      );

  String get displaySpeed {
    if (currentSpeed < 1024) return '${currentSpeed.toStringAsFixed(0)} B/s';
    if (currentSpeed < 1024 * 1024) return '${(currentSpeed / 1024).toStringAsFixed(1)} KB/s';
    if (currentSpeed < 1024 * 1024 * 1024) {
      return '${(currentSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(currentSpeed / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }

  String get displayTotalSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get displayDownloadedSize {
    if (downloadedBytes < 1024) return '$downloadedBytes B';
    if (downloadedBytes < 1024 * 1024) return '${(downloadedBytes / 1024).toStringAsFixed(1)} KB';
    if (downloadedBytes < 1024 * 1024 * 1024) {
      return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(downloadedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Duration get elapsedTime {
    if (startTime == null) return Duration.zero;
    return DateTime.now().difference(startTime!);
  }

  String get displayElapsedTime {
    return _formatDuration(elapsedTime);
  }

  Duration get estimatedTotalDuration {
    if (currentSpeed <= 0 || totalBytes == 0) return Duration.zero;
    final totalSeconds = totalBytes / currentSpeed;
    return Duration(seconds: totalSeconds.round());
  }

  String get displayEstimatedDuration {
    if (currentSpeed <= 0) return '--:--';
    return _formatDuration(estimatedTotalDuration);
  }

  Duration get estimatedRemainingTime {
    if (currentSpeed <= 0) return Duration.zero;
    final remainingBytes = totalBytes - downloadedBytes;
    if (remainingBytes <= 0) return Duration.zero;
    final remainingSeconds = remainingBytes / currentSpeed;
    return Duration(seconds: remainingSeconds.round());
  }

  String get displayRemainingTime {
    if (currentSpeed <= 0) return '--:--';
    if (downloadedBytes >= totalBytes) return '0:00';
    return _formatDuration(estimatedRemainingTime);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get statusText {
    if (!isDownloading && error != null) return 'Failed';
    if (!isDownloading && progress >= 1.0 && items.isNotEmpty) return 'Completed';
    if (isDownloading) return 'Downloading';
    return 'Idle';
  }

  DownloadState copyWith({
    bool? isDownloading,
    String? fileName,
    double? progress,
    int? currentFileIndex,
    int? totalFiles,
    String? error,
    DateTime? startTime,
    double? currentSpeed,
    int? totalBytes,
    int? downloadedBytes,
    List<DownloadItem>? items,
  }) {
    return DownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      fileName: fileName ?? this.fileName,
      progress: progress ?? this.progress,
      currentFileIndex: currentFileIndex ?? this.currentFileIndex,
      totalFiles: totalFiles ?? this.totalFiles,
      error: error,
      startTime: startTime ?? this.startTime,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      items: items ?? this.items,
    );
  }

  DownloadState clear() {
    return const DownloadState();
  }
}

/// Notifier for managing download state.
class DownloadStateNotifier extends StateNotifier<DownloadState> {
  final WebDavService _service;
  DateTime? _lastSpeedUpdateTime;
  int _lastDownloadedBytes = 0;
  int _completedFilesBytes = 0;
  final List<_DownloadTask> _queue = [];
  bool _processing = false;

  DownloadStateNotifier(this._service) : super(const DownloadState());

  /// Download a single file. Returns true on success.
  Future<bool> downloadFile({
    required String remoteName,
    required String localPath,
    int? fileSize,
  }) async {
    final completer = Completer<bool>();
    _queue.add(_DownloadTask(
      remoteName: remoteName,
      localPath: localPath,
      fileSize: fileSize ?? 0,
      completer: completer,
    ));

    // Add pending item to state
    final itemId = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = p.basename(localPath);
    final total = fileSize ?? 0;
    final item = DownloadItem(
      id: itemId,
      remotePath: remoteName,
      localPath: localPath,
      fileName: fileName,
      fileSize: total,
      status: DownloadStatus.pending,
    );

    state = state.copyWith(
      isDownloading: state.isDownloading || _processing,
      fileName: state.isDownloading ? state.fileName : fileName,
      totalFiles: state.totalFiles + 1,
      totalBytes: state.totalBytes + total,
      items: [...state.items, item],
    );

    _ensureProcessing();
    return completer.future;
  }

  void _ensureProcessing() {
    if (_processing) return;
    _processing = true;
    _processNextTask();
  }

  Future<void> _processNextTask() async {
    int completedBytes = 0;

    while (_queue.isNotEmpty) {
      final task = _queue.removeAt(0);

      _lastDownloadedBytes = 0;
      _lastSpeedUpdateTime = DateTime.now();

      final itemId = _findPendingItemId(task.remoteName);
      if (itemId == null) continue;

      final updatedItems = state.items.map((i) {
        if (i.id == itemId) {
          return i.copyWith(status: DownloadStatus.downloading);
        }
        return i;
      }).toList();

      state = state.copyWith(
        isDownloading: true,
        fileName: p.basename(task.localPath),
        currentFileIndex: state.completedCount + 1,
        items: updatedItems,
      );

      final result = await _service.downloadFile(
        task.remoteName,
        task.localPath,
        onProgress: (downloaded, total) {
          if (!mounted) return;
          final overallProgress = state.totalBytes > 0
              ? (completedBytes + downloaded) / state.totalBytes
              : 0.0;
          _updateProgressWithOverall(downloaded, total, itemId, overallProgress, completedBytes + downloaded);
        },
      );

      if (!mounted) return;

      if (result.isSuccess) {
        _markItemCompleted(itemId);
        completedBytes += task.fileSize;
      } else {
        _markItemFailed(itemId, result.error?.userMessage);
        completedBytes += task.fileSize;
      }

      task.completer.complete(result.isSuccess);
    }

    state = state.copyWith(
      isDownloading: false,
      currentSpeed: 0,
      progress: 1.0,
      downloadedBytes: state.totalBytes,
    );
    _processing = false;
  }

  String? _findPendingItemId(String remoteName) {
    for (final item in state.items) {
      if (item.status == DownloadStatus.pending && item.remotePath == remoteName) {
        return item.id;
      }
    }
    return null;
  }

  void _markItemCompleted(String itemId) {
    final updatedItems = state.items.map((i) {
      if (i.id == itemId) {
        return i.copyWith(status: DownloadStatus.completed, progress: 1.0);
      }
      return i;
    }).toList();

    state = state.copyWith(
      items: updatedItems,
    );
  }

  void _markItemFailed(String itemId, String? error) {
    final updatedItems = state.items.map((i) {
      if (i.id == itemId) {
        return i.copyWith(status: DownloadStatus.failed, error: error);
      }
      return i;
    }).toList();

    final hasError = updatedItems.any((i) => i.status == DownloadStatus.failed);
    state = state.copyWith(
      error: hasError ? error : null,
      items: updatedItems,
    );
  }

  /// Download a folder.
  Future<WebDavResult<int>> downloadFolder({
    required String remoteFolderName,
    required String localFolderPath,
  }) async {
    if (state.isDownloading) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Download already in progress'),
      );
    }

    _lastDownloadedBytes = 0;
    _lastSpeedUpdateTime = DateTime.now();
    _completedFilesBytes = 0;

    final folderName = p.basename(localFolderPath);

    state = DownloadState(
      isDownloading: true,
      fileName: folderName,
      progress: 0,
      currentFileIndex: 0,
      totalFiles: 0,
      startTime: DateTime.now(),
    );

    String? currentItemId;

    final result = await _service.downloadFolder(
      remoteFolderName,
      localFolderPath,
      onFilesCollected: (files) {
        if (!mounted) return;
        final items = files.asMap().entries.map((entry) {
          final index = entry.key;
          final file = entry.value;
          return DownloadItem(
            id: '${DateTime.now().millisecondsSinceEpoch}_$index',
            remotePath: file.remotePath,
            localPath: p.join(localFolderPath, file.relativePath),
            fileName: file.fileName,
            fileSize: file.fileSize,
            status: DownloadStatus.pending,
          );
        }).toList();

        final totalBytes = files.fold<int>(0, (sum, f) => sum + f.fileSize);

        state = state.copyWith(
          fileName: folderName,
          totalFiles: files.length,
          totalBytes: totalBytes,
          items: items,
        );
      },
      onProgress: (fileName, current, total, downloadedBytes, totalBytes) {
        if (!mounted) return;

        final items = List<DownloadItem>.from(state.items);
        final itemIndex = current - 1;

        if (itemIndex >= 0 && itemIndex < items.length) {
          final item = items[itemIndex];
          final newItemId = item.id;

          if (currentItemId != null && currentItemId != newItemId) {
            final prevIndex = items.indexWhere((i) => i.id == currentItemId);
            if (prevIndex >= 0) {
              _completedFilesBytes += items[prevIndex].fileSize;
              items[prevIndex] = items[prevIndex].copyWith(
                status: DownloadStatus.completed,
                progress: 1.0,
              );
            }
          }

          currentItemId = newItemId;

          final itemProgress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
          items[itemIndex] = item.copyWith(
            status: DownloadStatus.downloading,
            progress: itemProgress,
          );
        }

        final totalDownloaded = _completedFilesBytes + downloadedBytes;
        final overallProgress = state.totalBytes > 0 ? totalDownloaded / state.totalBytes : 0.0;

        final now = DateTime.now();
        final elapsed = _lastSpeedUpdateTime != null
            ? now.difference(_lastSpeedUpdateTime!).inMilliseconds
            : 0;

        if (elapsed >= 300) {
          final bytesDelta = totalDownloaded - _lastDownloadedBytes;
          final speed = (bytesDelta > 0 && elapsed > 0)
              ? bytesDelta / (elapsed / 1000)
              : 0.0;
          state = state.copyWith(
            progress: overallProgress,
            currentSpeed: speed,
            downloadedBytes: totalDownloaded,
            items: items,
          );
          _lastDownloadedBytes = totalDownloaded;
          _lastSpeedUpdateTime = now;
        } else {
          state = state.copyWith(
            progress: overallProgress,
            downloadedBytes: totalDownloaded,
            items: items,
          );
        }
      },
    );

    if (!mounted) return result;

    if (result.isSuccess) {
      final downloadedCount = result.data ?? 0;
      final updatedItems = state.items.map((i) {
        final alreadyCompleted = i.status == DownloadStatus.completed;
        final isCurrent = i.status == DownloadStatus.downloading;
        if (isCurrent && downloadedCount < state.totalFiles) {
          return i.copyWith(status: DownloadStatus.failed);
        }
        if (isCurrent) {
          return i.copyWith(status: DownloadStatus.completed, progress: 1.0);
        }
        return alreadyCompleted ? i.copyWith(progress: 1.0) : i;
      }).toList();

      state = state.copyWith(
        isDownloading: false,
        fileName: folderName,
        progress: 1.0,
        currentSpeed: 0,
        downloadedBytes: state.totalBytes,
        items: updatedItems,
      );
    } else {
      final updatedItems = state.items.map((i) {
        if (i.status == DownloadStatus.downloading) {
          return i.copyWith(
            status: DownloadStatus.failed,
            error: result.error?.userMessage,
          );
        }
        return i;
      }).toList();

      state = state.copyWith(
        isDownloading: false,
        fileName: folderName,
        error: result.error?.userMessage,
        currentSpeed: 0,
        items: updatedItems,
      );
    }

    return result;
  }

  void _updateProgressWithOverall(int downloadedBytes, int totalBytes,
      String itemId, double overallProgress, int totalDownloaded) {
    final now = DateTime.now();
    final elapsed = _lastSpeedUpdateTime != null
        ? now.difference(_lastSpeedUpdateTime!).inMilliseconds
        : 0;

    final updatedItems = state.items.map((i) {
      if (i.id == itemId) {
        final fileProgress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
        return i.copyWith(progress: fileProgress);
      }
      return i;
    }).toList();

    if (elapsed >= 300) {
      final bytesDelta = totalDownloaded - _lastDownloadedBytes;
      final speed = (bytesDelta > 0 && elapsed > 0)
          ? bytesDelta / (elapsed / 1000)
          : 0.0;
      state = state.copyWith(
        progress: overallProgress,
        currentSpeed: speed,
        downloadedBytes: totalDownloaded,
        items: updatedItems,
      );
      _lastDownloadedBytes = totalDownloaded;
      _lastSpeedUpdateTime = now;
    } else {
      state = state.copyWith(
        progress: overallProgress,
        downloadedBytes: totalDownloaded,
        items: updatedItems,
      );
    }
  }

  /// Remove completed items from the list.
  void clearCompleted() {
    if (state.isDownloading) return;
    final remaining = state.items
        .where((i) => i.status != DownloadStatus.completed)
        .toList();
    state = remaining.isEmpty
        ? state.clear()
        : state.copyWith(
            items: remaining,
            error: remaining.any((i) => i.status == DownloadStatus.failed) ? state.error : null,
          );
  }

  /// Remove failed items from the list.
  void clearFailed() {
    if (state.isDownloading) return;
    final remaining = state.items
        .where((i) => i.status != DownloadStatus.failed)
        .toList();
    state = remaining.isEmpty
        ? state.clear()
        : state.copyWith(items: remaining, error: null);
  }

  /// Remove all items from the list.
  void clearAll() {
    _queue.clear();
    _processing = false;
    state = state.clear();
  }
}

class _DownloadTask {
  final String remoteName;
  final String localPath;
  final int fileSize;
  final Completer<bool> completer;

  _DownloadTask({
    required this.remoteName,
    required this.localPath,
    required this.fileSize,
    required this.completer,
  });
}

/// Provider for download state management (uses Files service).
final downloadStateProvider =
    StateNotifierProvider<DownloadStateNotifier, DownloadState>((ref) {
  final service = ref.watch(webDavFilesServiceProvider);
  return DownloadStateNotifier(service);
});
