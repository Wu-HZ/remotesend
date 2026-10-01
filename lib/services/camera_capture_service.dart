import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class CameraCaptureService {
  final ImagePicker _picker;
  final Future<Directory> Function() _directory;
  final bool supportsRecovery;
  final Map<String, String> _preparedPaths = {};

  CameraCaptureService({
    ImagePicker? picker,
    Future<Directory> Function()? directory,
    bool? supportsRecovery,
  }) : _picker = picker ?? ImagePicker(),
       _directory = directory ?? _captureDirectory,
       supportsRecovery = supportsRecovery ?? Platform.isAndroid;

  static Future<Directory> _captureDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'camera_captures'));
  }

  Future<String?> capture() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
    );
    return photo == null ? null : _prepare(photo);
  }

  Future<List<String>> recover() async {
    if (!supportsRecovery) return [];
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return [];
    if (response.exception != null) throw response.exception!;
    final paths = <String>{};
    for (final photo in response.files ?? <XFile>[]) {
      paths.add(await _prepare(photo));
    }
    return paths.toList();
  }

  Future<String> _prepare(XFile photo) async {
    final source = p.normalize(photo.path);
    final prepared = _preparedPaths[source];
    if (prepared != null && await File(prepared).exists()) return prepared;

    final directory = await _directory();
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final extension = p.extension(photo.path);
    final target = File(
      p.join(
        directory.path,
        'photo_${timestamp}_${const Uuid().v4()}$extension',
      ),
    );
    try {
      await File(photo.path).copy(target.path);
      await target.setLastModified(DateTime.now());
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
    _preparedPaths[source] = target.path;
    return target.path;
  }

  Future<void> cleanExpired(Set<String> Function() protectedPaths) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await for (final entity in directory.list(followLinks: false)) {
      // 仅清理本功能创建的普通文件，不跟随链接或处理其他目录。
      if (entity is! File || !p.basename(entity.path).startsWith('photo_')) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff) &&
            !protectedPaths().contains(entity.path)) {
          await entity.delete();
        }
      } on FileSystemException {
        // 清理失败不影响拍照或重试，下次启动再清理。
      }
    }
  }
}
