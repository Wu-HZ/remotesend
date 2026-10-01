import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for pending upload queue.
class PendingUploadState {
  final List<String> filePaths;
  final bool isSubmitting;

  const PendingUploadState({
    this.filePaths = const [],
    this.isSubmitting = false,
  });

  PendingUploadState copyWith({List<String>? filePaths, bool? isSubmitting}) {
    return PendingUploadState(
      filePaths: filePaths ?? this.filePaths,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

/// Notifier for managing files waiting to be uploaded.
class PendingUploadNotifier extends StateNotifier<PendingUploadState> {
  PendingUploadNotifier() : super(const PendingUploadState());

  void addFiles(List<String> paths) {
    final updated = [...state.filePaths, ...paths];
    state = state.copyWith(filePaths: updated);
  }

  void removeFile(String path) {
    final updated = state.filePaths.where((p) => p != path).toList();
    state = state.copyWith(filePaths: updated);
  }

  List<String> beginSubmission() {
    if (state.isSubmitting || state.filePaths.isEmpty) return [];
    final paths = List<String>.from(state.filePaths);
    // 先移交快照，后续追加或上传失败回退的文件不属于本批次。
    state = const PendingUploadState(isSubmitting: true);
    return paths;
  }

  void finishSubmission({List<String> unsubmitted = const []}) {
    state = PendingUploadState(filePaths: [...unsubmitted, ...state.filePaths]);
  }

  void clear() {
    if (state.isSubmitting) return;
    state = const PendingUploadState();
  }
}

/// Provider for pending upload state.
final pendingUploadProvider =
    StateNotifierProvider<PendingUploadNotifier, PendingUploadState>((ref) {
      return PendingUploadNotifier();
    });
