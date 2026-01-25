/// Status of a download item.
enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
}

/// Represents a single file in the download queue.
class DownloadItem {
  final String id;
  final String remotePath;
  final String localPath;
  final String fileName;
  final int fileSize;
  final DownloadStatus status;
  final double progress;
  final String? error;

  const DownloadItem({
    required this.id,
    required this.remotePath,
    required this.localPath,
    required this.fileName,
    required this.fileSize,
    this.status = DownloadStatus.pending,
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

  DownloadItem copyWith({
    String? id,
    String? remotePath,
    String? localPath,
    String? fileName,
    int? fileSize,
    DownloadStatus? status,
    double? progress,
    String? error,
  }) {
    return DownloadItem(
      id: id ?? this.id,
      remotePath: remotePath ?? this.remotePath,
      localPath: localPath ?? this.localPath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error,
    );
  }
}
