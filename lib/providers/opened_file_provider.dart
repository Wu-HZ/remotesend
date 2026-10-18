import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/opened_file_service.dart';
import 'pending_upload_provider.dart';

class OpenedFileState {
  const OpenedFileState({
    this.openedCount = 0,
    this.errorRevision = 0,
    this.error,
  });

  final int openedCount;
  final int errorRevision;
  final OpenedFileError? error;
}

final openedFileSupportedProvider = Provider<bool>((ref) => Platform.isAndroid);
final openedFileServiceProvider = Provider<OpenedFileService>(
  (ref) => OpenedFileService(),
);
final openedFileProvider =
    StateNotifierProvider<OpenedFileNotifier, OpenedFileState>((ref) {
      return OpenedFileNotifier(ref, ref.watch(openedFileServiceProvider));
    });

class OpenedFileNotifier extends StateNotifier<OpenedFileState> {
  OpenedFileNotifier(this._ref, this._service) : super(const OpenedFileState());

  final Ref _ref;
  final OpenedFileService _service;
  final Set<String> _handledIds = {};
  StreamSubscription<OpenedFileEvent>? _subscription;

  void initialize() {
    if (_subscription != null || !_ref.read(openedFileSupportedProvider)) {
      return;
    }
    _subscription = _service.events.listen(
      _receive,
      onError: (Object _) {
        _reportError(OpenedFileError.failed);
      },
    );
  }

  void _receive(OpenedFileEvent event) {
    if (!mounted || !_handledIds.add(event.id)) return;
    if (_handledIds.length > 256) _handledIds.remove(_handledIds.first);
    if (event.path case final path?) {
      // Opening a file is never permission to upload it immediately, even when
      // normal sharing/dragging is configured for instant sending.
      _ref.read(pendingUploadProvider.notifier).addFiles([path]);
      state = OpenedFileState(
        openedCount: state.openedCount + 1,
        errorRevision: state.errorRevision,
      );
    } else {
      _reportError(event.error ?? OpenedFileError.failed);
    }
  }

  void _reportError(OpenedFileError error) {
    if (!mounted) return;
    state = OpenedFileState(
      openedCount: state.openedCount,
      errorRevision: state.errorRevision + 1,
      error: error,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel().catchError((Object _) {}));
    super.dispose();
  }
}
