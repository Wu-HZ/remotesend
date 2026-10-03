import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/services/download_path_service.dart';

class _UnwritablePreferences extends Fake implements SharedPreferences {
  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DownloadPathService paths;
  ServerConfig server(String id, [String name = '服务器']) => ServerConfig(
    id: id,
    name: name,
    serverUrl: 'https://example.invalid',
    username: 'test',
    password: 'test',
    createdAt: DateTime(2026),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('server_download_paths_');
    paths = DownloadPathService(defaultDirectory: () async => root);
  });
  tearDown(() => root.delete(recursive: true));

  test('不同服务器的同名文件使用独立子目录', () async {
    final a = await paths.downloadPath(
      configuredDirectory: root.path,
      server: server('a'),
      fileName: 'report.txt',
    );
    final b = await paths.downloadPath(
      configuredDirectory: root.path,
      server: server('b'),
      fileName: 'report.txt',
    );
    expect(p.dirname(a), isNot(p.dirname(b)));
    expect(p.basename(a), 'report.txt');
    expect(p.basename(b), 'report.txt');
    expect(p.dirname(p.dirname(a)), root.path);
    expect(await Directory(p.dirname(a)).exists(), isTrue);
  });

  test('未配置根目录时使用统一默认值', () async {
    expect(await paths.rootPath(''), root.path);
    final target = await paths.downloadPath(
      configuredDirectory: '',
      server: server('a'),
      fileName: 'file.txt',
    );
    expect(p.isWithin(root.path, target), isTrue);
  });

  test('便携下载目录跟随程序移动，且保留服务器子目录隔离', () async {
    var executable = p.join(root.path, 'usb-a', 'RemoteSend.exe');
    final portable = DownloadPathService(executablePath: () => executable);
    final stored = AppConfig(
      downloadLocation: DownloadPathService.portableDownloadsLocation,
    );
    final restored = AppConfig.fromJsonString(stored.toJsonString());
    expect(
      restored.downloadLocation,
      DownloadPathService.portableDownloadsLocation,
    );

    final first = await portable.downloadPath(
      configuredDirectory: restored.downloadLocation,
      server: server('a'),
      fileName: 'report.txt',
    );
    expect(
      p.dirname(p.dirname(first)),
      p.join(root.path, 'usb-a', 'Downloads'),
    );
    await File(first).writeAsString('old copy');

    executable = p.join(root.path, 'usb-b', 'RemoteSend.exe');
    final second = await portable.downloadPath(
      configuredDirectory: restored.downloadLocation,
      server: server('a'),
      fileName: 'report.txt',
    );
    expect(
      p.dirname(p.dirname(second)),
      p.join(root.path, 'usb-b', 'Downloads'),
    );
    expect(p.basename(p.dirname(second)), p.basename(p.dirname(first)));
    expect(await File(first).readAsString(), 'old copy');
  });

  test('未选择便携位置时继续使用默认或用户选择的目录', () async {
    final portable = DownloadPathService(
      defaultDirectory: () async => root,
      executablePath: () => p.join(root.path, 'app', 'RemoteSend.exe'),
    );
    expect(await portable.rootPath(''), root.path);
    expect(
      await portable.rootPath(p.join(root.path, 'custom')),
      p.join(root.path, 'custom'),
    );
  });

  test('服务器改名与重新加载后仍使用首次分配的目录', () async {
    final original = await paths.serverDirectory(
      configuredDirectory: root.path,
      server: server('a', '旧名称'),
    );
    final reloaded = DownloadPathService(defaultDirectory: () async => root);
    final renamed = await reloaded.serverDirectory(
      configuredDirectory: root.path,
      server: server('a', '新名称'),
    );
    expect(renamed, original);
    expect(p.basename(renamed), startsWith('旧名称-'));
  });

  test('修改总目录仅影响新的保存路径，不移动原文件', () async {
    final a = await paths.downloadPath(
      configuredDirectory: root.path,
      server: server('a'),
      fileName: 'file.txt',
    );
    await File(a).writeAsString('old');
    final newRoot = p.join(root.path, 'new-root');
    final b = await paths.downloadPath(
      configuredDirectory: newRoot,
      server: server('a'),
      fileName: 'file.txt',
    );
    expect(p.basename(p.dirname(a)), p.basename(p.dirname(b)));
    expect(p.dirname(p.dirname(b)), newRoot);
    expect(await File(a).readAsString(), 'old');
  });

  test('并发首次分配和重载不会产生重复或丢失映射', () async {
    final directories = await Future.wait([
      paths.serverDirectory(
        configuredDirectory: root.path,
        server: server('a'),
      ),
      paths.serverDirectory(
        configuredDirectory: root.path,
        server: server('b'),
      ),
      paths.serverDirectory(
        configuredDirectory: root.path,
        server: server('a'),
      ),
    ]);
    expect(directories[0], directories[2]);
    expect(directories[0], isNot(directories[1]));
    final reloaded = DownloadPathService();
    expect(
      await reloaded.serverDirectory(
        configuredDirectory: root.path,
        server: server('b'),
      ),
      directories[1],
    );
  });

  test('短标识与已有目录名冲突时加长，不合并服务器', () async {
    final hash = sha256.convert(utf8.encode('b')).toString();
    SharedPreferences.setMockInitialValues({
      DownloadPathService.foldersPreferenceKey: jsonEncode({
        'a': 'SAME-${hash.substring(0, 8)}',
      }),
    });
    final target = await paths.serverDirectory(
      configuredDirectory: root.path,
      server: server('b', 'same'),
    );
    expect(p.basename(target), 'same-${hash.substring(0, 12)}');
  });

  test('服务器名称非法字符和 Windows 保留名称被处理', () async {
    for (final name in ['../a\\b:*?"<>|', 'CON', '  ... ', '名称.  ']) {
      final target = await paths.serverDirectory(
        configuredDirectory: root.path,
        server: server(name, name),
      );
      expect(p.dirname(target), root.path);
      expect(p.basename(target), isNot(matches(RegExp(r'[<>:"/\\|?*]'))));
    }
    final long = await paths.serverDirectory(
      configuredDirectory: root.path,
      server: server('long', '很长' * 100),
    );
    expect(p.basename(long).runes.length, lessThanOrEqualTo(69));
  });

  test('文件名路径穿越及无效名称被拒绝', () async {
    for (final name in [
      '../file',
      r'..\file',
      '/file',
      'C:\\file',
      '..',
      '',
      'file.',
      'NUL.txt',
    ]) {
      await expectLater(
        paths.downloadPath(
          configuredDirectory: root.path,
          server: server('a'),
          fileName: name,
        ),
        throwsArgumentError,
      );
    }
  });

  test('持久化映射中的不安全名称不被复用', () async {
    SharedPreferences.setMockInitialValues({
      DownloadPathService.foldersPreferenceKey: jsonEncode({'a': '../outside'}),
    });
    await expectLater(
      paths.serverDirectory(
        configuredDirectory: root.path,
        server: server('a'),
      ),
      throwsFormatException,
    );
  });

  test('已有文件和文件夹保留，新下载使用独立名称', () async {
    final first = await paths.downloadPath(
      configuredDirectory: root.path,
      server: server('a'),
      fileName: 'report.txt',
    );
    await File(first).writeAsString('old');
    final second = await paths.downloadPath(
      configuredDirectory: root.path,
      server: server('a'),
      fileName: 'report.txt',
    );
    expect(p.basename(second), 'report (1).txt');
    expect(await File(first).readAsString(), 'old');
    final folder = await paths.downloadPath(
      configuredDirectory: root.path,
      server: server('a'),
      fileName: 'docs.v1',
      isDirectory: true,
    );
    await File(p.join(folder, 'old.txt')).writeAsString('keep');
    final another = await paths.downloadPath(
      configuredDirectory: root.path,
      server: server('a'),
      fileName: 'docs.v1',
      isDirectory: true,
    );
    expect(p.basename(another), 'docs.v1 (1)');
    expect(await File(p.join(folder, 'old.txt')).readAsString(), 'keep');
  });

  test('目录创建失败不会降级写到下载根目录', () async {
    final expected = await paths.serverDirectory(
      configuredDirectory: root.path,
      server: server('a'),
    );
    await Directory(expected).delete();
    await File(expected).writeAsString('blocking file');
    await expectLater(
      paths.downloadPath(
        configuredDirectory: root.path,
        server: server('a'),
        fileName: 'report.txt',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(p.join(root.path, 'report.txt')).exists(), isFalse);
  });

  test('服务器目录不能是指向其他位置的链接', () async {
    final directory = await paths.serverDirectory(
      configuredDirectory: root.path,
      server: server('a'),
    );
    await Directory(directory).delete();
    final elsewhere = await Directory(p.join(root.path, 'elsewhere')).create();
    if (Platform.isWindows) {
      final result = await Process.run('cmd', [
        '/d',
        '/c',
        'mklink',
        '/J',
        directory,
        elsewhere.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    } else {
      await Link(directory).create(elsewhere.path);
    }
    await expectLater(
      paths.downloadPath(
        configuredDirectory: root.path,
        server: server('a'),
        fileName: 'report.txt',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await elsewhere.list().isEmpty, isTrue);
  });

  test('映射无法保存时明确失败，不创建未登记目录', () async {
    final failing = DownloadPathService(
      preferences: () async => _UnwritablePreferences(),
    );
    await expectLater(
      failing.serverDirectory(
        configuredDirectory: root.path,
        server: server('a'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await root.list().isEmpty, isTrue);
  });
}
