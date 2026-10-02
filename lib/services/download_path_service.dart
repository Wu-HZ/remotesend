import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';

class DownloadPathService {
  static const foldersPreferenceKey = 'download_server_folders';
  final Future<Directory> Function() _defaultDirectory;
  final Future<SharedPreferences> Function() _preferences;
  Map<String, String>? _folders;
  Future<void> _pending = Future.value();

  DownloadPathService({
    Future<Directory> Function()? defaultDirectory,
    Future<SharedPreferences> Function()? preferences,
  }) : _defaultDirectory = defaultDirectory ?? _systemDirectory,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static Future<Directory> _systemDirectory() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final home =
          Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(p.join(home, 'Downloads'));
      }
    } else if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) return external;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<String> rootPath(String configuredDirectory) async {
    final configured = configuredDirectory.trim();
    final root = configured.isNotEmpty
        ? configured
        : (await _defaultDirectory()).path;
    return p.normalize(p.absolute(root));
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static final _invalidCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]');
  static final _reservedName = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  );

  static bool _safeSegment(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !_invalidCharacters.hasMatch(value) &&
      !_reservedName.hasMatch(value) &&
      !value.endsWith('.') &&
      !value.endsWith(' ');

  static String _serverLabel(String name) {
    var label = name.replaceAll(_invalidCharacters, '_').trim();
    label = String.fromCharCodes(label.runes.take(60));
    label = label.replaceAll(RegExp(r'[. ]+$'), '');
    if (label.isEmpty || label == '.' || label == '..') label = 'server';
    if (_reservedName.hasMatch(label)) label = '_$label';
    return label;
  }

  Future<String> _folderName(ServerConfig server) async {
    if (server.id.isEmpty) throw ArgumentError('服务器标识不能为空');
    final preferences = await _preferences();
    if (_folders == null) {
      final raw = preferences.getString(foldersPreferenceKey);
      final decoded = raw == null ? <String, dynamic>{} : jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('下载目录映射无效');
      final loaded = <String, String>{};
      final used = <String>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            !_safeSegment(entry.value as String) ||
            !used.add((entry.value as String).toLowerCase())) {
          throw const FormatException('下载目录映射含无效或重复的目录名');
        }
        loaded[entry.key as String] = entry.value as String;
      }
      _folders = loaded;
    }
    final existing = _folders![server.id];
    if (existing != null) return existing;

    final prefix = _serverLabel(server.name);
    final hash = sha256.convert(utf8.encode(server.id)).toString();
    final used = _folders!.values.map((name) => name.toLowerCase()).toSet();
    for (var length = 8; length <= hash.length; length += 4) {
      final name = '$prefix-${hash.substring(0, length)}';
      if (used.contains(name.toLowerCase())) continue;
      final updated = {..._folders!, server.id: name};
      if (!await preferences.setString(
        foldersPreferenceKey,
        jsonEncode(updated),
      )) {
        throw const FileSystemException('无法保存服务器下载目录映射');
      }
      _folders = updated;
      return name;
    }
    throw const FileSystemException('无法分配独立的服务器下载目录');
  }

  Future<String> _serverDirectory(
    String configuredDirectory,
    ServerConfig server,
  ) async {
    final root = Directory(await rootPath(configuredDirectory));
    final name = await _folderName(server);
    await root.create(recursive: true);
    final directory = Directory(p.join(root.path, name));
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('服务器下载目录不是普通文件夹', directory.path);
    }
    await directory.create();
    final expected = p.join(await root.resolveSymbolicLinks(), name);
    if (!p.equals(await directory.resolveSymbolicLinks(), expected)) {
      throw FileSystemException('服务器下载目录超出预期位置', directory.path);
    }
    return directory.path;
  }

  Future<String> serverDirectory({
    required String configuredDirectory,
    required ServerConfig server,
  }) => _serialized(() => _serverDirectory(configuredDirectory, server));

  Future<String> downloadPath({
    required String configuredDirectory,
    required ServerConfig server,
    required String fileName,
    bool isDirectory = false,
  }) => _serialized(() async {
    if (!_safeSegment(fileName)) throw ArgumentError('下载文件名无效：$fileName');
    final directory = await _serverDirectory(configuredDirectory, server);
    final desired = p.join(directory, fileName);
    if (!p.isWithin(directory, desired)) throw ArgumentError('下载路径超出服务器目录');
    final path = await availableDownloadPath(desired, isDirectory: isDirectory);
    if (isDirectory) await Directory(path).create();
    return path;
  });
}

/// Returns [desiredPath] when it is free, otherwise finds a sibling path such
/// as `name (1).ext`.
///
/// Downloads must not write directly over an existing file. Besides avoiding
/// accidental data loss, this also allows an updated remote file to be
/// downloaded while the previous local copy is open and locked by another
/// application (notably on Windows).
Future<String> availableDownloadPath(
  String desiredPath, {
  bool isDirectory = false,
}) async {
  if (!await _pathExists(desiredPath)) return desiredPath;

  final directory = p.dirname(desiredPath);
  final fileName = p.basename(desiredPath);
  final extension = isDirectory ? '' : p.extension(fileName);
  final baseName = isDirectory
      ? fileName
      : p.basenameWithoutExtension(fileName);
  var suffix = 1;

  while (true) {
    final candidate = p.join(directory, '$baseName ($suffix)$extension');
    if (!await _pathExists(candidate)) return candidate;
    suffix++;
  }
}

Future<bool> _pathExists(String path) async {
  return await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}
