import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/gotify_models.dart';
import '../models/server_config.dart';
import '../services/webdav_service.dart';
import 'config_provider.dart';
import 'download_cache_provider.dart';
import 'download_state_provider.dart';
import 'gotify_provider.dart';
import 'message_history_provider.dart';

class IncomingTransfer {
  const IncomingTransfer({
    required this.eventId,
    required this.fileName,
    required this.senderName,
    required this.status,
    this.localPath,
    this.error,
  });

  final String eventId;
  final String fileName;
  final String senderName;
  final String status;
  final String? localPath;
  final String? error;

  IncomingTransfer copyWith({
    String? status,
    String? localPath,
    String? error,
  }) {
    return IncomingTransfer(
      eventId: eventId,
      fileName: fileName,
      senderName: senderName,
      status: status ?? this.status,
      localPath: localPath ?? this.localPath,
      error: error,
    );
  }
}

class GotifyCoordinatorState {
  const GotifyCoordinatorState({
    this.incomingTransfers = const [],
    this.lastReceivedFile,
    this.lastError,
    this.lastReceipt,
  });

  final List<IncomingTransfer> incomingTransfers;
  final IncomingTransfer? lastReceivedFile;
  final String? lastError;
  final String? lastReceipt;

  GotifyCoordinatorState copyWith({
    List<IncomingTransfer>? incomingTransfers,
    IncomingTransfer? lastReceivedFile,
    String? lastError,
    String? lastReceipt,
    bool clearError = false,
  }) {
    return GotifyCoordinatorState(
      incomingTransfers: incomingTransfers ?? this.incomingTransfers,
      lastReceivedFile: lastReceivedFile ?? this.lastReceivedFile,
      lastError: clearError ? null : lastError ?? this.lastError,
      lastReceipt: lastReceipt ?? this.lastReceipt,
    );
  }
}

/// Turns Gotify events into one-shot WebDAV operations. It intentionally has
/// no timer and never scans WebDAV for changes.
class GotifyCoordinatorNotifier extends StateNotifier<GotifyCoordinatorState> {
  GotifyCoordinatorNotifier(this._gotify, this._ref)
    : super(const GotifyCoordinatorState()) {
    _subscription = _gotify.events.listen(_handleEvent);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        _retryWaitingFiles();
        _gotify.replayPendingEvents();
      }
    });
    _ref.listen(configProvider, (previous, next) {
      if (previous?.valueOrNull != next.valueOrNull) {
        _retryWaitingFiles();
        _gotify.replayPendingEvents();
      }
    });
  }

  final GotifyNotifier _gotify;
  final Ref _ref;
  late final StreamSubscription<RemoteSendEvent> _subscription;
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  final List<RemoteSendEvent> _fileQueue = [];
  final Map<String, RemoteSendEvent> _waitingFiles = {};
  bool _processingFiles = false;
  Timer? _textRefreshDebounce;
  final List<RemoteSendEvent> _pendingTextEvents = [];

  void _handleEvent(RemoteSendEvent event) {
    switch (event.type) {
      case RemoteSendEvent.textChanged:
        _scheduleTextRefresh(event);
      case RemoteSendEvent.fileReady:
        _enqueueFile(event);
      case RemoteSendEvent.fileReceived:
        final fileName = event.payload['fileName'] as String? ?? '';
        state = state.copyWith(
          lastReceipt: '$fileName received by ${event.senderName}',
        );
        unawaited(_gotify.acknowledgeEvent(event.eventId));
    }
  }

  void _scheduleTextRefresh(RemoteSendEvent event) {
    final config = _ref.read(configProvider).valueOrNull;
    final server = config?.activeTextServer;
    if (server == null ||
        event.payload['serverKey'] != webDavServerKey(server)) {
      return;
    }

    if (!_pendingTextEvents.any((item) => item.eventId == event.eventId)) {
      _pendingTextEvents.add(event);
    }
    _textRefreshDebounce?.cancel();
    _textRefreshDebounce = Timer(const Duration(milliseconds: 300), () async {
      final pending = List<RemoteSendEvent>.from(_pendingTextEvents);
      _pendingTextEvents.clear();
      final byDate = <String, List<RemoteSendEvent>>{};
      for (final item in pending) {
        final date = item.payload['date'] as String? ?? '';
        if (date.isNotEmpty) byDate.putIfAbsent(date, () => []).add(item);
      }
      for (final entry in byDate.entries) {
        final success = await _ref
            .read(messageHistoryProvider.notifier)
            .refreshFromRemoteChange(entry.key);
        if (!mounted) return;
        if (success) {
          for (final item in entry.value) {
            await _gotify.acknowledgeEvent(item.eventId);
          }
        }
      }
    });
  }

  void _enqueueFile(RemoteSendEvent event) {
    if (_fileQueue.any((item) => item.eventId == event.eventId) ||
        state.incomingTransfers.any((item) => item.eventId == event.eventId)) {
      return;
    }

    final transfer = IncomingTransfer(
      eventId: event.eventId,
      fileName: event.payload['fileName'] as String? ?? 'file',
      senderName: event.senderName,
      status: 'queued',
    );
    state = state.copyWith(
      incomingTransfers: _bounded([...state.incomingTransfers, transfer]),
      clearError: true,
    );
    _fileQueue.add(event);
    _processFiles();
  }

  Future<void> _processFiles() async {
    if (_processingFiles) return;
    _processingFiles = true;
    try {
      while (_fileQueue.isNotEmpty && mounted) {
        final event = _fileQueue.removeAt(0);
        await _processFile(event);
      }
    } finally {
      _processingFiles = false;
    }
  }

  Future<void> _processFile(RemoteSendEvent event) async {
    final config = _ref.read(configProvider).valueOrNull;
    if (config == null) return;

    final gotify = config.gotify;
    final fileName = event.payload['fileName'] as String? ?? 'file';
    final fileSize = (event.payload['fileSize'] as num?)?.toInt() ?? 0;
    final remotePath = event.payload['remotePath'] as String? ?? '';
    final serverKey = event.payload['serverKey'] as String? ?? '';

    if (!gotify.autoDownloadEnabled) {
      _waitForPolicy(event);
      return;
    }
    if (gotify.maxAutoDownloadBytes > 0 &&
        fileSize > gotify.maxAutoDownloadBytes) {
      _waitForPolicy(
        event,
        error: 'File exceeds this device auto-download limit',
      );
      return;
    }
    if (gotify.wifiOnly && !await _isUnmeteredNetwork()) {
      _waitForPolicy(event, error: 'Waiting for Wi-Fi or Ethernet');
      return;
    }
    if (!_isSafeRemoteFilePath(remotePath)) {
      _setTransfer(
        event.eventId,
        status: 'failed',
        error: 'Unsafe remote file path',
      );
      await _gotify.acknowledgeEvent(event.eventId);
      return;
    }

    final server = _matchingServer(config.servers, serverKey);
    if (server == null) {
      _waitForPolicy(event, error: 'Matching WebDAV server is not configured');
      return;
    }

    try {
      final localPath = await _createLocalPath(
        config.downloadLocation,
        fileName,
      );
      final relativeRemotePath = remotePath.substring(
        '/RemoteSend/Files/'.length,
      );
      final serviceOverride = WebDavService()..initializeWithServer(server);

      _setTransfer(event.eventId, status: 'downloading', localPath: localPath);
      final success = await _ref
          .read(downloadStateProvider.notifier)
          .downloadFile(
            remoteName: relativeRemotePath,
            localPath: localPath,
            fileSize: fileSize,
            serviceOverride: serviceOverride,
          );
      if (!mounted) return;
      if (!success) {
        throw Exception('WebDAV download failed');
      }

      final downloaded = File(localPath);
      if (fileSize > 0 && await downloaded.length() != fileSize) {
        await downloaded.delete();
        throw Exception('Downloaded file size does not match the sender');
      }

      final remoteFile = RemoteFile(
        name: fileName,
        path: remotePath,
        size: fileSize,
        isDirectory: false,
      );
      await _ref
          .read(downloadCacheProvider.notifier)
          .markDownloaded(
            serverId: server.id,
            file: remoteFile,
            localPath: localPath,
          );

      final completed = _setTransfer(
        event.eventId,
        status: 'completed',
        localPath: localPath,
      );
      state = state.copyWith(lastReceivedFile: completed, clearError: true);
      await _gotify.publishFileReceived(event);
      await _gotify.acknowledgeEvent(event.eventId);
    } catch (error) {
      _waitForPolicy(event, error: error.toString());
      state = state.copyWith(lastError: error.toString());
    }
  }

  void _waitForPolicy(RemoteSendEvent event, {String? error}) {
    _waitingFiles[event.eventId] = event;
    _setTransfer(event.eventId, status: 'waiting', error: error);
  }

  void _retryWaitingFiles() {
    if (_waitingFiles.isEmpty) return;
    final waiting = _waitingFiles.values.toList();
    _waitingFiles.clear();
    for (final event in waiting) {
      if (!_fileQueue.any((item) => item.eventId == event.eventId)) {
        _setTransfer(event.eventId, status: 'queued');
        _fileQueue.add(event);
      }
    }
    _processFiles();
  }

  IncomingTransfer _setTransfer(
    String eventId, {
    required String status,
    String? localPath,
    String? error,
  }) {
    IncomingTransfer? updated;
    final transfers = state.incomingTransfers.map((item) {
      if (item.eventId != eventId) return item;
      updated = item.copyWith(
        status: status,
        localPath: localPath,
        error: error,
      );
      return updated!;
    }).toList();
    state = state.copyWith(incomingTransfers: transfers);
    return updated ??
        IncomingTransfer(
          eventId: eventId,
          fileName: 'file',
          senderName: 'Unknown',
          status: status,
          localPath: localPath,
          error: error,
        );
  }

  static ServerConfig? _matchingServer(List<ServerConfig> servers, String key) {
    for (final server in servers.where((item) => item.enabled)) {
      if (webDavServerKey(server) == key) return server;
    }
    return null;
  }

  static bool _isSafeRemoteFilePath(String path) {
    if (!path.startsWith('/RemoteSend/Files/')) return false;
    final relative = path.substring('/RemoteSend/Files/'.length);
    return relative.isNotEmpty &&
        !relative.split('/').any((segment) => segment == '..');
  }

  static Future<bool> _isUnmeteredNetwork() async {
    final connectivity = await Connectivity().checkConnectivity();
    return connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet);
  }

  static Future<String> _createLocalPath(
    String configuredDirectory,
    String unsafeFileName,
  ) async {
    Directory directory;
    if (configuredDirectory.trim().isNotEmpty) {
      directory = Directory(configuredDirectory.trim());
    } else if (Platform.isAndroid) {
      directory =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    await directory.create(recursive: true);

    final fileName = p.basename(unsafeFileName);
    var candidate = p.join(directory.path, fileName);
    if (!await File(candidate).exists()) return candidate;

    final extension = p.extension(fileName);
    final baseName = p.basenameWithoutExtension(fileName);
    var suffix = 1;
    do {
      candidate = p.join(directory.path, '$baseName ($suffix)$extension');
      suffix++;
    } while (await File(candidate).exists());
    return candidate;
  }

  static List<IncomingTransfer> _bounded(List<IncomingTransfer> transfers) {
    const maxItems = 50;
    return transfers.length <= maxItems
        ? transfers
        : transfers.sublist(transfers.length - maxItems);
  }

  @override
  void dispose() {
    _textRefreshDebounce?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_connectivitySubscription.cancel());
    super.dispose();
  }
}

final gotifyCoordinatorProvider =
    StateNotifierProvider<GotifyCoordinatorNotifier, GotifyCoordinatorState>((
      ref,
    ) {
      final gotify = ref.watch(gotifyProvider.notifier);
      return GotifyCoordinatorNotifier(gotify, ref);
    });
