import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/camera_capture_service.dart';
import 'pending_upload_provider.dart';
import 'upload_queue_provider.dart';

enum CameraCaptureError {
  permissionDenied,
  unavailable,
  fileAccess,
  failed,
  recoveryFailed,
}

class CameraCaptureState {
  final bool isBusy;
  final CameraCaptureError? error;
  final int recoveredCount;

  const CameraCaptureState({
    this.isBusy = false,
    this.error,
    this.recoveredCount = 0,
  });
}

final cameraSupportedProvider = Provider<bool>((ref) {
  return Platform.isAndroid || Platform.isIOS;
});

final cameraCaptureServiceProvider = Provider<CameraCaptureService>((ref) {
  return CameraCaptureService();
});

final cameraCaptureProvider =
    StateNotifierProvider<CameraCaptureNotifier, CameraCaptureState>((ref) {
      return CameraCaptureNotifier(
        ref,
        ref.watch(cameraCaptureServiceProvider),
      );
    });

class CameraCaptureNotifier extends StateNotifier<CameraCaptureState> {
  final Ref _ref;
  final CameraCaptureService _service;
  Future<void>? _initialization;

  CameraCaptureNotifier(this._ref, this._service)
    : super(const CameraCaptureState());

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!_ref.read(cameraSupportedProvider)) return;
    state = const CameraCaptureState(isBusy: true);
    var recoveredCount = 0;
    CameraCaptureError? error;
    try {
      final paths = await _service.recover();
      if (!mounted) return;
      final existing = _ref.read(pendingUploadProvider).filePaths.toSet();
      final recovered = paths.toSet().difference(existing).toList();
      _ref.read(pendingUploadProvider.notifier).addFiles(recovered);
      recoveredCount = recovered.length;
    } catch (_) {
      error = CameraCaptureError.recoveryFailed;
    }
    if (!mounted) return;
    try {
      await _service.cleanExpired(
        () => {
          ..._ref.read(pendingUploadProvider).filePaths,
          ..._ref.read(uploadQueueProvider).items.map((item) => item.localPath),
        },
      );
    } catch (_) {
      // 清理暂存失败不能阻止新照片进入待发送列表。
    }
    if (mounted) {
      state = CameraCaptureState(error: error, recoveredCount: recoveredCount);
    }
  }

  Future<void> capture() async {
    if (!_ref.read(cameraSupportedProvider) || state.isBusy) return;
    await initialize();
    if (!mounted ||
        state.isBusy ||
        _ref.read(pendingUploadProvider).isSubmitting) {
      return;
    }
    state = CameraCaptureState(
      isBusy: true,
      recoveredCount: state.recoveredCount,
    );
    CameraCaptureError? error;
    try {
      final path = await _service.capture();
      if (!mounted) return;
      if (path != null &&
          !_ref.read(pendingUploadProvider).filePaths.contains(path)) {
        _ref.read(pendingUploadProvider.notifier).addFiles([path]);
      }
    } on PlatformException catch (e) {
      error = switch (e.code) {
        'camera_access_denied' ||
        'camera_access_restricted' ||
        'camera_access_denied_without_prompt' =>
          CameraCaptureError.permissionDenied,
        'no_available_camera' ||
        'camera_unavailable' => CameraCaptureError.unavailable,
        _ => CameraCaptureError.failed,
      };
    } on FileSystemException {
      error = CameraCaptureError.fileAccess;
    } catch (_) {
      error = CameraCaptureError.failed;
    } finally {
      if (mounted) {
        state = CameraCaptureState(
          error: error,
          recoveredCount: state.recoveredCount,
        );
      }
    }
  }
}
