import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/providers/camera_capture_provider.dart';
import 'package:remote_send/providers/pending_upload_provider.dart';
import 'package:remote_send/providers/upload_queue_provider.dart';
import 'package:remote_send/services/camera_capture_service.dart';

class _CameraService extends CameraCaptureService {
  String? photo;
  Object? failure;
  List<String> recovered = [];
  Completer<String?>? captureResult;
  int captureCalls = 0;
  int recoverCalls = 0;
  final events = <String>[];

  @override
  Future<String?> capture() async {
    captureCalls++;
    if (failure != null) throw failure!;
    return captureResult == null ? photo : captureResult!.future;
  }

  @override
  Future<List<String>> recover() async {
    recoverCalls++;
    events.add('recover');
    return recovered;
  }

  @override
  Future<void> cleanExpired(Set<String> Function() protectedPaths) async {
    events.add('cleanup');
  }
}

void main() {
  late _CameraService service;
  late ProviderContainer container;

  setUp(() {
    service = _CameraService();
    container = ProviderContainer(
      overrides: [
        cameraSupportedProvider.overrideWithValue(true),
        cameraCaptureServiceProvider.overrideWithValue(service),
        uploadQueueProvider.overrideWith((ref) {
          throw StateError('拍照不应创建上传队列');
        }),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('拍照仅追加待发送，不覆盖已有文件或创建上传任务', () async {
    container.read(pendingUploadProvider.notifier).addFiles(['old.txt']);
    service.photo = 'photo.jpg';
    await container.read(cameraCaptureProvider.notifier).capture();
    expect(container.read(pendingUploadProvider).filePaths, [
      'old.txt',
      'photo.jpg',
    ]);
    expect(container.read(cameraCaptureProvider).isBusy, isFalse);
    expect(container.read(cameraCaptureProvider).error, isNull);
  });

  test('取消拍照保持待发送列表不变', () async {
    container.read(pendingUploadProvider.notifier).addFiles(['old.txt']);
    await container.read(cameraCaptureProvider.notifier).capture();
    expect(container.read(pendingUploadProvider).filePaths, ['old.txt']);
    expect(container.read(cameraCaptureProvider).error, isNull);
  });

  test('拍照期间重复点击只打开一次相机', () async {
    final notifier = container.read(cameraCaptureProvider.notifier);
    await notifier.initialize();
    service.captureResult = Completer<String?>();
    final first = notifier.capture();
    await Future<void>.delayed(Duration.zero);
    await notifier.capture();
    expect(service.captureCalls, 1);
    service.captureResult!.complete('photo.jpg');
    await first;
    expect(container.read(pendingUploadProvider).filePaths, ['photo.jpg']);
  });

  test('权限拒绝后解除忙碌状态，可以重新拍摄', () async {
    service.failure = PlatformException(code: 'camera_access_denied');
    final notifier = container.read(cameraCaptureProvider.notifier);
    await notifier.capture();
    expect(container.read(cameraCaptureProvider).isBusy, isFalse);
    expect(
      container.read(cameraCaptureProvider).error,
      CameraCaptureError.permissionDenied,
    );
    service.failure = null;
    service.photo = 'retry.jpg';
    await notifier.capture();
    expect(container.read(cameraCaptureProvider).error, isNull);
    expect(container.read(pendingUploadProvider).filePaths, ['retry.jpg']);
  });

  test('不可用相机和文件异常分别报告，不追加无效文件', () async {
    final notifier = container.read(cameraCaptureProvider.notifier);
    service.failure = PlatformException(code: 'no_available_camera');
    await notifier.capture();
    expect(
      container.read(cameraCaptureProvider).error,
      CameraCaptureError.unavailable,
    );
    service.failure = const FileSystemException('disk full');
    await notifier.capture();
    expect(
      container.read(cameraCaptureProvider).error,
      CameraCaptureError.fileAccess,
    );
    expect(container.read(pendingUploadProvider).filePaths, isEmpty);
  });

  test('恢复只执行一次并去重，清理在恢复之后执行', () async {
    service.recovered = ['recovered.jpg', 'recovered.jpg'];
    final notifier = container.read(cameraCaptureProvider.notifier);
    await notifier.initialize();
    await notifier.initialize();
    expect(service.recoverCalls, 1);
    expect(service.events, ['recover', 'cleanup']);
    expect(container.read(pendingUploadProvider).filePaths, ['recovered.jpg']);
    expect(container.read(cameraCaptureProvider).recoveredCount, 1);
  });

  test('发送批次交接期间不能拍照', () async {
    final pending = container.read(pendingUploadProvider.notifier);
    pending.addFiles(['sending.jpg']);
    pending.beginSubmission();
    await container.read(cameraCaptureProvider.notifier).capture();
    expect(service.captureCalls, 0);
    pending.finishSubmission();
  });

  test('桌面端不会启动相机或执行恢复', () async {
    final desktop = ProviderContainer(
      overrides: [
        cameraSupportedProvider.overrideWithValue(false),
        cameraCaptureServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(desktop.dispose);
    final notifier = desktop.read(cameraCaptureProvider.notifier);
    await notifier.initialize();
    await notifier.capture();
    expect(service.captureCalls, 0);
    expect(service.recoverCalls, 0);
  });
}
