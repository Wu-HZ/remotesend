import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/webdav_service.dart';

const _downloadCacheKey = 'download_cache';

class DownloadCacheEntry {
  const DownloadCacheEntry({
    required this.localPath,
    required this.isDirectory,
    this.remoteSize,
    this.remoteModifiedTime,
    this.remoteETag,
  });

  final String localPath;
  final bool isDirectory;
  final int? remoteSize;
  final DateTime? remoteModifiedTime;
  final String? remoteETag;

  Map<String, dynamic> toJson() {
    return {
      'localPath': localPath,
      'isDirectory': isDirectory,
      'remoteSize': remoteSize,
      'remoteModifiedTime': remoteModifiedTime?.toIso8601String(),
      'remoteETag': remoteETag,
    };
  }

  factory DownloadCacheEntry.fromJson(Map<String, dynamic> json) {
    return DownloadCacheEntry(
      localPath: json['localPath'] as String,
      isDirectory: json['isDirectory'] as bool? ?? false,
      remoteSize: json['remoteSize'] as int?,
      remoteModifiedTime: json['remoteModifiedTime'] == null
          ? null
          : DateTime.parse(json['remoteModifiedTime'] as String),
      remoteETag: json['remoteETag'] as String?,
    );
  }
}

class DownloadCacheState {
  const DownloadCacheState({this.entries = const {}});

  final Map<String, DownloadCacheEntry> entries;

  static String keyFor(String serverId, RemoteFile file) {
    final remotePath = file.path.isNotEmpty ? file.path : file.name;
    return '$serverId::$remotePath';
  }

  bool isDownloaded({required String serverId, required RemoteFile file}) {
    final entry = entries[keyFor(serverId, file)];
    if (entry == null || entry.isDirectory != file.isDirectory) return false;
    if (entry.remoteSize != file.size) return false;
    if (entry.remoteETag != null && file.eTag != null) {
      if (entry.remoteETag != file.eTag) return false;
    } else if (entry.remoteModifiedTime != file.modifiedTime) {
      return false;
    }

    try {
      if (file.isDirectory) {
        return Directory(entry.localPath).existsSync();
      }

      final localFile = File(entry.localPath);
      if (!localFile.existsSync()) return false;
      return file.size == null || localFile.lengthSync() == file.size;
    } catch (_) {
      return false;
    }
  }

  String? localPathFor({required String serverId, required RemoteFile file}) {
    if (!isDownloaded(serverId: serverId, file: file)) return null;
    return entries[keyFor(serverId, file)]!.localPath;
  }

  Map<String, dynamic> toJson() {
    return {
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    };
  }

  factory DownloadCacheState.fromJson(Map<String, dynamic> json) {
    final entries = <String, DownloadCacheEntry>{};
    for (final item in json.entries) {
      try {
        if (item.value is Map) {
          entries[item.key] = DownloadCacheEntry.fromJson(
            Map<String, dynamic>.from(item.value as Map),
          );
        }
      } catch (_) {
        // Ignore malformed cache entries and keep the remaining entries.
      }
    }
    return DownloadCacheState(entries: entries);
  }
}

class DownloadCacheNotifier extends StateNotifier<DownloadCacheState> {
  DownloadCacheNotifier() : super(const DownloadCacheState()) {
    _ready = _load();
  }

  late final Future<void> _ready;
  bool _changedBeforeLoad = false;

  /// Completes after the persisted cache has been loaded (or loading failed).
  Future<void> get ready => _ready;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_downloadCacheKey);
      if (!_changedBeforeLoad && raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          state = DownloadCacheState.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
    } catch (_) {
      // Keep an empty cache if preferences cannot be read.
    }
  }

  Future<void> markDownloaded({
    required String serverId,
    required RemoteFile file,
    required String localPath,
  }) async {
    _changedBeforeLoad = true;
    final updatedEntries = Map<String, DownloadCacheEntry>.from(state.entries);
    updatedEntries[DownloadCacheState.keyFor(
      serverId,
      file,
    )] = DownloadCacheEntry(
      localPath: localPath,
      isDirectory: file.isDirectory,
      remoteSize: file.size,
      remoteModifiedTime: file.modifiedTime,
      remoteETag: file.eTag,
    );
    state = DownloadCacheState(entries: updatedEntries);

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _downloadCacheKey,
        jsonEncode(state.toJson()),
      );
    } catch (_) {
      // The in-memory cache still prevents duplicate downloads this session.
    }
  }
}

final downloadCacheProvider =
    StateNotifierProvider<DownloadCacheNotifier, DownloadCacheState>(
      (ref) => DownloadCacheNotifier(),
    );
