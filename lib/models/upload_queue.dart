/// Status of an upload item.
enum UploadStatus {
  pending,
  uploading,
  completed,
  failed,
}

/// Represents a single file in the upload queue.
class UploadItem {
  final String id;
  final String localPath;
  final String remotePath;
  final String fileName;
  final int fileSize;
  final UploadStatus status;
  final double progress;
  final String? error;

  const UploadItem({
    required this.id,
    required this.localPath,
    required this.remotePath,
    required this.fileName,
    required this.fileSize,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.error,
  });

  String get displaySize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  UploadItem copyWith({
    String? id,
    String? localPath,
    String? remotePath,
    String? fileName,
    int? fileSize,
    UploadStatus? status,
    double? progress,
    String? error,
  }) {
    return UploadItem(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error,
    );
  }
}

/// State of the entire upload queue.
class UploadQueueState {
  final List<UploadItem> items;
  final bool isProcessing;
  final int totalBytes;
  final int uploadedBytes;
  final double currentSpeed; // bytes per second
  final DateTime? startTime;

  const UploadQueueState({
    this.items = const [],
    this.isProcessing = false,
    this.totalBytes = 0,
    this.uploadedBytes = 0,
    this.currentSpeed = 0,
    this.startTime,
  });

  /// Get count of pending items.
  int get pendingCount => items.where((i) => i.status == UploadStatus.pending).length;

  /// Get count of completed items.
  int get completedCount => items.where((i) => i.status == UploadStatus.completed).length;

  /// Get count of failed items.
  int get failedCount => items.where((i) => i.status == UploadStatus.failed).length;

  /// Get the currently uploading item.
  UploadItem? get currentItem => items.cast<UploadItem?>().firstWhere(
        (i) => i?.status == UploadStatus.uploading,
        orElse: () => null,
      );

  /// Get overall progress (0.0 to 1.0).
  double get overallProgress {
    if (totalBytes == 0) return 0;
    return uploadedBytes / totalBytes;
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

  /// Get display string for uploaded size.
  String get displayUploadedSize {
    if (uploadedBytes < 1024) return '$uploadedBytes B';
    if (uploadedBytes < 1024 * 1024) return '${(uploadedBytes / 1024).toStringAsFixed(1)} KB';
    if (uploadedBytes < 1024 * 1024 * 1024) {
      return '${(uploadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(uploadedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get display string for speed.
  String get displaySpeed {
    if (currentSpeed < 1024) return '${currentSpeed.toStringAsFixed(0)} B/s';
    if (currentSpeed < 1024 * 1024) return '${(currentSpeed / 1024).toStringAsFixed(1)} KB/s';
    if (currentSpeed < 1024 * 1024 * 1024) {
      return '${(currentSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(currentSpeed / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }

  /// Get elapsed time since upload started.
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
    final remainingBytes = totalBytes - uploadedBytes;
    if (remainingBytes <= 0) return Duration.zero;
    final remainingSeconds = remainingBytes / currentSpeed;
    return Duration(seconds: remainingSeconds.round());
  }

  /// Get estimated remaining time as formatted string.
  String get displayRemainingTime {
    if (currentSpeed <= 0) return '--:--';
    if (uploadedBytes >= totalBytes) return '0:00';
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
    if (!isProcessing && items.isEmpty) return 'Idle';
    if (!isProcessing && completedCount == items.length) return 'Completed';
    if (isProcessing) return 'Uploading';
    if (failedCount > 0) return 'Failed';
    return 'Idle';
  }

  UploadQueueState copyWith({
    List<UploadItem>? items,
    bool? isProcessing,
    int? totalBytes,
    int? uploadedBytes,
    double? currentSpeed,
    DateTime? startTime,
  }) {
    return UploadQueueState(
      items: items ?? this.items,
      isProcessing: isProcessing ?? this.isProcessing,
      totalBytes: totalBytes ?? this.totalBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      startTime: startTime ?? this.startTime,
    );
  }

  /// Create a cleared state.
  UploadQueueState clear() {
    return const UploadQueueState();
  }
}
