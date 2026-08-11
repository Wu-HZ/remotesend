import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for pending upload queue.
class PendingUploadState {
  final List<String> filePaths;

  const PendingUploadState({this.filePaths = const []});

  PendingUploadState copyWith({List<String>? filePaths}) {
    return PendingUploadState(filePaths: filePaths ?? this.filePaths);
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

  void clear() {
    state = const PendingUploadState();
  }
}

/// Provider for pending upload state.
final pendingUploadProvider =
    StateNotifierProvider<PendingUploadNotifier, PendingUploadState>((ref) {
  return PendingUploadNotifier();
});
