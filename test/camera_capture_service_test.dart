import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:remote_send/services/camera_capture_service.dart';

class _Picker extends ImagePicker {
  XFile? photo;
  LostDataResponse lost = LostDataResponse.empty();
  int recoveryCalls = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(source, ImageSource.camera);
    expect(maxWidth, isNull);
    expect(maxHeight, isNull);
    expect(imageQuality, isNull);
    expect(requestFullMetadata, isFalse);
    return photo;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    recoveryCalls++;
    return lost;
  }
}

void main() {
  late Directory root;
  late Directory captures;
  late _Picker picker;
  late CameraCaptureService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('camera_service_test_');
    captures = Directory(p.join(root.path, 'captures'));
    picker = _Picker();
    service = CameraCaptureService(
      picker: picker,
      directory: () async => captures,
      supportsRecovery: true,
    );
  });

  tearDown(() async => root.delete(recursive: true));

  test('拍照保留字节和格式，独立暂存且文件名唯一', () async {
    final original = File(p.join(root.path, 'camera.HEIC'));
    await original.writeAsBytes([0, 1, 2, 250, 255]);
    picker.photo = XFile(original.path);
    final first = (await service.capture())!;
    final another = File(p.join(root.path, 'another.HEIC'));
    await another.writeAsBytes([3, 4, 5]);
    picker.photo = XFile(another.path);
    final second = (await service.capture())!;

    expect(first, isNot(second));
    expect(p.dirname(first), captures.path);
    expect(p.extension(first), '.HEIC');
    expect(await File(first).readAsBytes(), [0, 1, 2, 250, 255]);
    expect(await original.exists(), isTrue);
    expect(await File(second).readAsBytes(), [3, 4, 5]);
  });

  test('取消拍摄不创建暂存目录', () async {
    expect(await service.capture(), isNull);
    expect(await captures.exists(), isFalse);
  });

  test('恢复结果与正常结果共用暂存文件并去重', () async {
    final source = File(p.join(root.path, 'photo.jpg'));
    await source.writeAsBytes([1, 2, 3]);
    picker.photo = XFile(source.path);
    final captured = await service.capture();
    picker.lost = LostDataResponse(
      files: [XFile(source.path), XFile(source.path)],
      type: RetrieveType.image,
    );
    expect(await service.recover(), [captured]);
    expect(await captures.list().length, 1);
  });

  test('非 Android 不调用丢失结果恢复', () async {
    final ios = CameraCaptureService(
      picker: picker,
      directory: () async => captures,
      supportsRecovery: false,
    );
    expect(await ios.recover(), isEmpty);
    expect(picker.recoveryCalls, 0);
  });

  test('来源丢失时报错，不留下半成品', () async {
    picker.photo = XFile(p.join(root.path, 'missing.jpg'));
    await expectLater(service.capture(), throwsA(isA<FileSystemException>()));
    expect(await captures.list().length, 0);
  });

  test('仅清理过期且无引用的拍摄文件', () async {
    await captures.create();
    final expired = File(p.join(captures.path, 'photo_expired.jpg'));
    final protected = File(p.join(captures.path, 'photo_protected.jpg'));
    final recent = File(p.join(captures.path, 'photo_recent.jpg'));
    final unrelated = File(p.join(captures.path, 'unrelated.txt'));
    for (final file in [expired, protected, recent, unrelated]) {
      await file.writeAsString('data');
    }
    final old = DateTime.now().subtract(const Duration(days: 8));
    for (final file in [expired, protected, unrelated]) {
      await file.setLastModified(old);
    }
    await service.cleanExpired(() => {protected.path});
    expect(await expired.exists(), isFalse);
    for (final file in [protected, recent, unrelated]) {
      expect(await file.exists(), isTrue);
    }
  });
}
