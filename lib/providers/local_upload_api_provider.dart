import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/app_config.dart';
import '../models/upload_queue.dart';
import '../services/local_upload_api_server.dart';
import 'config_provider.dart';
import 'upload_queue_provider.dart';

class LocalUploadApiState {
  final bool running;
  final int? port;
  final String? error;
  const LocalUploadApiState({this.running = false, this.port, this.error});
}

/// Production uses a fixed port; an ephemeral port keeps integration tests isolated.
final localUploadApiPortProvider = Provider<int>(
  (ref) => LocalUploadApiServer.defaultPort,
);

class LocalUploadApiNotifier extends StateNotifier<LocalUploadApiState> {
  final Ref _ref;
  LocalUploadApiServer? _server;
  AppConfig? _desiredConfig;
  Future<void> _configuration = Future<void>.value();
  final Map<String, UploadItem> _jobs = {};
  final Set<String> _reservedPaths = {};

  LocalUploadApiNotifier(this._ref) : super(const LocalUploadApiState());

  /// Serialize enable/disable operations to prevent stale binds after a toggle.
  void configure(AppConfig? config) {
    _desiredConfig = config;
    _configuration = _configuration.then((_) => _applyConfiguration());
  }

  Future<void> _applyConfiguration() async {
    if (!mounted) return;
    final enabled =
        _desiredConfig?.localUploadApiEnabled == true &&
        _desiredConfig!.localUploadApiToken.isNotEmpty;
    if (!enabled) {
      final server = _server;
      _server = null;
      if (server != null) await server.close();
      if (mounted) state = const LocalUploadApiState();
      return;
    }
    if (_server != null) return;
    try {
      final server = await LocalUploadApiServer.bind(
        token: () {
          final config = _ref.read(configProvider).valueOrNull;
          return config?.localUploadApiEnabled == true
              ? config!.localUploadApiToken
              : '';
        },
        enqueue: _enqueue,
        lookup: _lookup,
        port: _ref.read(localUploadApiPortProvider),
      );
      if (!mounted || _desiredConfig?.localUploadApiEnabled != true) {
        await server.close();
        return;
      }
      _server = server;
      state = LocalUploadApiState(running: true, port: server.port);
    } on SocketException {
      if (mounted) {
        state = const LocalUploadApiState(
          error: 'Port 38764 is already in use',
        );
      }
    } catch (_) {
      if (mounted) {
        state = const LocalUploadApiState(error: 'Could not start local API');
      }
    }
  }

  Future<UploadItem> _enqueue(String path, bool overwrite) async {
    final config = _ref.read(configProvider).valueOrNull;
    final server = _ref.read(activeFilesServerProvider);
    if (config?.localUploadApiEnabled != true ||
        server == null ||
        !server.isConfigured) {
      throw const LocalUploadApiException(503, 'No active files server');
    }
    final name = p.basename(path);
    // Default to a unique name: no remote read/check-then-write race and no
    // accidental replacement of a build from a previous run.
    final unique = const Uuid().v4();
    final remoteName = overwrite
        ? name
        : '${p.basenameWithoutExtension(name)}-$unique${p.extension(name)}';
    final remotePath = '/RemoteSend/Files/$remoteName';
    if (_reservedPaths.contains(remotePath) ||
        _ref
            .read(uploadQueueProvider)
            .items
            .any(
              (item) =>
                  item.remotePath == remotePath &&
                  (item.status == UploadStatus.pending ||
                      item.status == UploadStatus.uploading),
            )) {
      throw const LocalUploadApiException(
        409,
        'Upload to this name is already in progress',
      );
    }
    if (_jobs.length >= 500) {
      _jobs.removeWhere(
        (_, job) =>
            job.status == UploadStatus.completed ||
            job.status == UploadStatus.failed,
      );
      if (_jobs.length >= 500) {
        throw const LocalUploadApiException(429, 'Too many active uploads');
      }
    }
    _reservedPaths.add(remotePath);
    try {
      // Recheck if the API was disabled while the request was being validated.
      if (_ref.read(configProvider).valueOrNull?.localUploadApiEnabled !=
          true) {
        throw const LocalUploadApiException(503, 'Upload API is disabled');
      }
      final id = await _ref
          .read(uploadQueueProvider.notifier)
          .addAutomatedFile(path, remoteName: remoteName);
      if (id == null) {
        throw const LocalUploadApiException(400, 'File no longer exists');
      }
      final item = _ref
          .read(uploadQueueProvider)
          .items
          .where((entry) => entry.id == id)
          .firstOrNull;
      if (item == null) {
        throw const LocalUploadApiException(503, 'Upload was cancelled');
      }
      _jobs[item.id] = item;
      return item;
    } finally {
      _reservedPaths.remove(remotePath);
    }
  }

  UploadItem? _lookup(String id) {
    if (!_jobs.containsKey(id)) return null;
    final current = _ref
        .read(uploadQueueProvider)
        .items
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (current != null) _jobs[id] = current;
    return _jobs[id];
  }

  void record(UploadQueueState queue) {
    if (_jobs.isEmpty) return;
    for (final id in _jobs.keys.toList()) {
      final item = queue.items.where((entry) => entry.id == id).firstOrNull;
      if (item != null) {
        _jobs[id] = item;
      } else {
        final last = _jobs[id]!;
        if (last.status != UploadStatus.completed &&
            last.status != UploadStatus.failed) {
          _jobs[id] = last.copyWith(
            status: UploadStatus.failed,
            error: 'Upload was cancelled or removed from the queue',
          );
        }
      }
    }
  }

  @override
  void dispose() {
    unawaited(_server?.close());
    super.dispose();
  }
}

/// Kept alive by the desktop app root (not by the Settings screen).
final localUploadApiProvider =
    StateNotifierProvider<LocalUploadApiNotifier, LocalUploadApiState>((ref) {
      final notifier = LocalUploadApiNotifier(ref);
      ref.listen<AsyncValue<AppConfig>>(configProvider, (_, next) {
        notifier.configure(next.valueOrNull);
      });
      ref.listen<UploadQueueState>(uploadQueueProvider, (_, next) {
        notifier.record(next);
      });
      notifier.configure(ref.read(configProvider).valueOrNull);
      return notifier;
    });
