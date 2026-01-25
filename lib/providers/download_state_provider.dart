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

  /// Get count of pending items.
  int get pendingCount => items.where((i) => i.status == DownloadStatus.pending).length;

  /// Get count of completed items.
  int get completedCount => items.where((i) => i.status == DownloadStatus.completed).length;

  /// Get count of failed items.
  int get failedCount => items.where((i) => i.status == DownloadStatus.failed).length;

  /// Get the currently downloading item.
  DownloadItem? get currentItem => items.cast<DownloadItem?>().firstWhere(
        (i) => i?.status == DownloadStatus.downloading,
        orElse: () => null,
      );

  /// Get display string for speed.
  String get displaySpeed {
    if (currentSpeed < 1024) return '${currentSpeed.toStringAsFixed(0)} B/s';
    if (currentSpeed < 1024 * 1024) return '${(currentSpeed / 1024).toStringAsFixed(1)} KB/s';
    if (currentSpeed < 1024 * 1024 * 1024) {
      return '${(currentSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(currentSpeed / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }

  /// Get display string for total size.
  String get displayTotalSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get display string for downloaded size.
  String get displayDownloadedSize {
    if (downloadedBytes < 1024) return '$downloadedBytes B';
    if (downloadedBytes < 1024 * 1024) return '${(downloadedBytes / 1024).toStringAsFixed(1)} KB';
    if (downloadedBytes < 1024 * 1024 * 1024) {
      return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(downloadedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get elapsed time since download started.
  Duration get elapsedTime {
    if (startTime == null) return Duration.zero;
    return DateTime.now().difference(startTime!);
  }

  /// Get elapsed time as formatted string.
  String get displayElapsedTime {
    return _formatDuration(elapsedTime);
  }

  /// Get estimated total duration based on current speed.
  Duration get estimatedTotalDuration {
    if (currentSpeed <= 0 || totalBytes == 0) return Duration.zero;
    final totalSeconds = totalBytes / currentSpeed;
    return Duration(seconds: totalSeconds.round());
  }

  /// Get estimated total duration as formatted string.
  String get displayEstimatedDuration {
    if (currentSpeed <= 0) return '--:--';
    return _formatDuration(estimatedTotalDuration);
  }

  /// Get estimated remaining time based on current speed.
  Duration get estimatedRemainingTime {
    if (currentSpeed <= 0) return Duration.zero;
    final remainingBytes = totalBytes - downloadedBytes;
    if (remainingBytes <= 0) return Duration.zero;
    final remainingSeconds = remainingBytes / currentSpeed;
    return Duration(seconds: remainingSeconds.round());
  }

  /// Get estimated remaining time as formatted string.
  String get displayRemainingTime {
    if (currentSpeed <= 0) return '--:--';
    if (downloadedBytes >= totalBytes) return '0:00';
    return _formatDuration(estimatedRemainingTime);
  }

  /// Format a duration as H:MM:SS or M:SS.
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get status text.
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

  DownloadStateNotifier(this._service) : super(const DownloadState());

  /// Download a single file.
  Future<bool> downloadFile({
    required String remoteName,
    required String localPath,
    int? fileSize,
  }) async {
    _lastDownloadedBytes = 0;
    _lastSpeedUpdateTime = DateTime.now();
    _completedFilesBytes = 0;

    final itemId = DateTime.now().millisecondsSinceEpoch.toString();
    final item = DownloadItem(
      id: itemId,
      remotePath: remoteName,
      localPath: localPath,
      fileName: p.basename(localPath),
      fileSize: fileSize ?? 0,
      status: DownloadStatus.downloading,
    );

    state = DownloadState(
      isDownloading: true,
      fileName: p.basename(localPath),
      progress: 0,
      currentFileIndex: 1,
      totalFiles: 1,
      startTime: DateTime.now(),
      totalBytes: fileSize ?? 0,
      items: [item],
    );

    final result = await _service.downloadFile(
      remoteName,
      localPath,
      onProgress: (downloaded, total) {
        if (!mounted) return;
        _updateProgress(downloaded, total, itemId);
      },
    );

    if (!mounted) return false;

    if (result.isSuccess) {
      final updatedItems = state.items.map((i) {
        if (i.id == itemId) {
          return i.copyWith(status: DownloadStatus.completed, progress: 1.0);
        }
        return i;
      }).toList();

      state = state.copyWith(
        isDownloading: false,
        progress: 1.0,
        currentSpeed: 0,
        downloadedBytes: state.totalBytes,
        items: updatedItems,
      );
      return true;
    } else {
      final updatedItems = state.items.map((i) {
        if (i.id == itemId) {
          return i.copyWith(
            status: DownloadStatus.failed,
            error: result.error?.userMessage,
          );
        }
        return i;
      }).toList();

      state = state.copyWith(
        isDownloading: false,
        error: result.error?.userMessage,
        currentSpeed: 0,
        items: updatedItems,
      );
      return false;
    }
  }

  /// Download a folder.
  Future<WebDavResult<int>> downloadFolder({
    required String remoteFolderName,
    required String localFolderPath,
  }) async {
    _lastDownloadedBytes = 0;
    _lastSpeedUpdateTime = DateTime.now();
    _completedFilesBytes = 0;

    state = DownloadState(
      isDownloading: true,
      fileName: p.basename(localFolderPath),
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
        // Create download items from collected files
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

        // Calculate total bytes
        final totalBytes = files.fold<int>(0, (sum, f) => sum + f.fileSize);

        state = state.copyWith(
          totalFiles: files.length,
          totalBytes: totalBytes,
          items: items,
        );
      },
      onProgress: (fileName, current, total, downloadedBytes, totalBytes) {
        if (!mounted) return;

        // Update current item status
        final items = List<DownloadItem>.from(state.items);
        final itemIndex = current - 1;

        if (itemIndex >= 0 && itemIndex < items.length) {
          final item = items[itemIndex];
          final newItemId = item.id;

          // If we moved to a new file, mark previous as completed and update completed bytes
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

          // Update current item progress
          final itemProgress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
          items[itemIndex] = item.copyWith(
            status: DownloadStatus.downloading,
            progress: itemProgress,
          );
        }

        // Calculate overall progress and downloaded bytes
        final totalDownloaded = _completedFilesBytes + downloadedBytes;
        final overallProgress = state.totalBytes > 0 ? totalDownloaded / state.totalBytes : 0.0;

        _updateProgressWithItems(downloadedBytes, totalBytes, items, overallProgress, totalDownloaded);

        state = state.copyWith(
          fileName: fileName,
          currentFileIndex: current,
          totalFiles: total,
          items: items,
        );
      },
    );

    if (!mounted) return result;

    if (result.isSuccess) {
      // Mark all items as completed
      final updatedItems = state.items.map((i) {
        return i.copyWith(status: DownloadStatus.completed, progress: 1.0);
      }).toList();

      state = state.copyWith(
        isDownloading: false,
        progress: 1.0,
        currentSpeed: 0,
        downloadedBytes: state.totalBytes,
        items: updatedItems,
      );
    } else {
      // Mark current item as failed
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
        error: result.error?.userMessage,
        currentSpeed: 0,
        items: updatedItems,
      );
    }

    return result;
  }

  void _updateProgress(int downloadedBytes, int totalBytes, String itemId) {
    final now = DateTime.now();
    final elapsed = _lastSpeedUpdateTime != null
        ? now.difference(_lastSpeedUpdateTime!).inMilliseconds
        : 0;

    // Use totalBytes from callback only if valid, otherwise keep existing state value
    final effectiveTotalBytes = totalBytes > 0 ? totalBytes : state.totalBytes;

    // Calculate progress
    final progress = effectiveTotalBytes > 0 ? downloadedBytes / effectiveTotalBytes : 0.0;

    // Update item progress
    final updatedItems = state.items.map((i) {
      if (i.id == itemId) {
        return i.copyWith(progress: progress);
      }
      return i;
    }).toList();

    // Update speed every 300ms or more
    if (elapsed >= 300) {
      final bytesDelta = downloadedBytes - _lastDownloadedBytes;
      if (bytesDelta > 0 && elapsed > 0) {
        // Calculate speed: bytes per second
        final speed = bytesDelta / (elapsed / 1000);
        state = state.copyWith(
          progress: progress,
          currentSpeed: speed,
          totalBytes: effectiveTotalBytes,
          downloadedBytes: downloadedBytes,
          items: updatedItems,
        );
      } else {
        state = state.copyWith(
          progress: progress,
          totalBytes: effectiveTotalBytes,
          downloadedBytes: downloadedBytes,
          items: updatedItems,
        );
      }
      _lastDownloadedBytes = downloadedBytes;
      _lastSpeedUpdateTime = now;
    } else {
      // Just update progress without speed calculation
      state = state.copyWith(
        progress: progress,
        totalBytes: effectiveTotalBytes,
        downloadedBytes: downloadedBytes,
        items: updatedItems,
      );
    }
  }

  void _updateProgressWithItems(
    int currentFileDownloaded,
    int currentFileTotal,
    List<DownloadItem> items,
    double overallProgress,
    int totalDownloaded,
  ) {
    final now = DateTime.now();
    final elapsed = _lastSpeedUpdateTime != null
        ? now.difference(_lastSpeedUpdateTime!).inMilliseconds
        : 0;

    // Update speed every 300ms or more
    if (elapsed >= 300) {
      final bytesDelta = totalDownloaded - _lastDownloadedBytes;
      if (bytesDelta > 0 && elapsed > 0) {
        // Calculate speed: bytes per second
        final speed = bytesDelta / (elapsed / 1000);
        state = state.copyWith(
          progress: overallProgress,
          currentSpeed: speed,
          downloadedBytes: totalDownloaded,
          items: items,
        );
      } else {
        state = state.copyWith(
          progress: overallProgress,
          downloadedBytes: totalDownloaded,
          items: items,
        );
      }
      _lastDownloadedBytes = totalDownloaded;
      _lastSpeedUpdateTime = now;
    } else {
      // Just update progress without speed calculation
      state = state.copyWith(
        progress: overallProgress,
        downloadedBytes: totalDownloaded,
        items: items,
      );
    }
  }

  /// Clear download state.
  void clear() {
    state = state.clear();
  }
}

/// Provider for download state management (uses Files service).
final downloadStateProvider =
    StateNotifierProvider<DownloadStateNotifier, DownloadState>((ref) {
  final service = ref.watch(webDavFilesServiceProvider);
  return DownloadStateNotifier(service);
});
