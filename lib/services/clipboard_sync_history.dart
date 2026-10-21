import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Device-local clipboard sync log. Files are stored in app support storage and
/// are never sent through Gotify, WebDAV, or the transfer history service.
class ClipboardSyncHistory {
  const ClipboardSyncHistory({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  static const recentWindow = Duration(days: 30);
  static const _directoryName = 'clipboard-sync-history';

  Future<Directory> _directory() async {
    final directory = directoryProvider == null
        ? Directory(
            '${(await getApplicationSupportDirectory()).path}/$_directoryName',
          )
        : await directoryProvider!();
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> record({
    required String eventId,
    required DateTime at,
    required String direction,
    required String deviceName,
    required String text,
  }) async {
    if (text.isEmpty || (direction != 'sent' && direction != 'received')) {
      return;
    }
    final directory = await _directory();
    final record = <String, Object>{
      'id': eventId,
      'at': at.toUtc().toIso8601String(),
      'direction': direction,
      'device': deviceName,
      'text': text,
    };
    final recent = File('${directory.path}/recent.jsonl');
    await recent.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
    await _archiveExpired(directory, DateTime.now().toUtc());
  }

  Future<List<ClipboardSyncHistoryRecord>> recent() async {
    final directory = await _directory();
    await _archiveExpired(directory, DateTime.now().toUtc());
    return _readLines(File('${directory.path}/recent.jsonl'));
  }

  Future<Map<String, List<ClipboardSyncHistoryRecord>>> archives() async {
    final directory = await _directory();
    await _archiveExpired(directory, DateTime.now().toUtc());
    final files = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              entry.path.endsWith('.jsonl') &&
              entry.uri.pathSegments.last != 'recent.jsonl',
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    final result = <String, List<ClipboardSyncHistoryRecord>>{};
    for (final file in files) {
      final month = file.uri.pathSegments.last.replaceFirst('.jsonl', '');
      result[month] = await _readLines(file);
    }
    return result;
  }

  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<List<ClipboardSyncHistoryRecord>> _readLines(File file) async {
    if (!await file.exists()) return const [];
    final records = <ClipboardSyncHistoryRecord>[];
    for (final line in await file.readAsLines()) {
      try {
        final value = jsonDecode(line);
        if (value is Map<String, dynamic>) {
          final record = ClipboardSyncHistoryRecord.fromJson(value);
          if (record != null) records.add(record);
        }
      } on FormatException {
        // Ignore a truncated/corrupt local line without losing other records.
      }
    }
    records.sort((a, b) => b.at.compareTo(a.at));
    return records;
  }

  Future<void> _archiveExpired(Directory directory, DateTime now) async {
    final recent = File('${directory.path}/recent.jsonl');
    if (!await recent.exists()) {
      return;
    }
    final cutoff = now.subtract(recentWindow);
    final keep = <String>[];
    final moved = <String, List<String>>{};
    for (final line in await recent.readAsLines()) {
      try {
        final value = jsonDecode(line);
        final at = value is Map<String, dynamic>
            ? DateTime.tryParse('${value['at']}')
            : null;
        if (at == null || !at.isBefore(cutoff)) {
          keep.add(line);
        } else {
          final month =
              '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}';
          moved.putIfAbsent(month, () => []).add(line);
        }
      } on FormatException {
        // Keep malformed rows for best-effort manual recovery.
        keep.add(line);
      }
    }
    for (final entry in moved.entries) {
      final archive = File('${directory.path}/${entry.key}.jsonl');
      await archive.writeAsString(
        '${entry.value.join('\n')}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
    final temp = File('${directory.path}/recent.jsonl.tmp');
    await temp.writeAsString(
      keep.isEmpty ? '' : '${keep.join('\n')}\n',
      flush: true,
    );
    await temp.rename(recent.path);
  }
}

class ClipboardSyncHistoryRecord {
  const ClipboardSyncHistoryRecord({
    required this.id,
    required this.at,
    required this.direction,
    required this.device,
    required this.text,
  });

  final String id;
  final DateTime at;
  final String direction;
  final String device;
  final String text;

  static ClipboardSyncHistoryRecord? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final at = DateTime.tryParse('${json['at']}');
    final direction = json['direction'];
    final device = json['device'];
    final text = json['text'];
    if (id is! String ||
        at == null ||
        (direction != 'sent' && direction != 'received') ||
        device is! String ||
        text is! String) {
      return null;
    }
    return ClipboardSyncHistoryRecord(
      id: id,
      at: at.toLocal(),
      direction: direction as String,
      device: device,
      text: text,
    );
  }
}
