import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns [desiredPath] when it is free, otherwise finds a sibling path such
/// as `name (1).ext`.
///
/// Downloads must not write directly over an existing file. Besides avoiding
/// accidental data loss, this also allows an updated remote file to be
/// downloaded while the previous local copy is open and locked by another
/// application (notably on Windows).
Future<String> availableDownloadPath(String desiredPath) async {
  if (!await _pathExists(desiredPath)) return desiredPath;

  final directory = p.dirname(desiredPath);
  final fileName = p.basename(desiredPath);
  final extension = p.extension(fileName);
  final baseName = p.basenameWithoutExtension(fileName);
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
