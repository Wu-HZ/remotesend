import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/gotify_models.dart';
import '../models/server_config.dart';
import '../services/download_path_service.dart';
import '../services/webdav_service.dart';
import 'app_visibility_provider.dart';
import 'config_provider.dart';
import 'download_cache_provider.dart';
import 'download_state_provider.dart';
import 'gotify_provider.dart';
import 'message_history_provider.dart';
import 'webdav_provider.dart';

String? selectNewestTextForClipboard(
  Iterable<RemoteSendEvent> events,
  Map<String, String> textByMessageId,
) {
  RemoteSendEvent? newest;
  for (final event in events) {
    final messageId =
        event.payload[RemoteSendEvent.newMessageIdPayloadKey] as String?;
    if (messageId == null || !textByMessageId.containsKey(messageId)) continue;
    if (newest == null || !event.createdAt.isBefore(newest.createdAt)) {
      newest = event;
    }
  }
  if (newest == null) return null;
  final messageId =
      newest.payload[RemoteSendEvent.newMessageIdPayloadKey] as String;
  return textByMessageId[messageId];
}

ReceiveLatencySample? _receiveLatency(
  Iterable<RemoteSendEvent> events,
  int webDavMilliseconds,
) {
  RemoteSendEvent? newest;
  for (final event in events) {
    if (newest == null || event.createdAt.isAfter(newest.createdAt)) {
      newest = event;
    }
  }
  if (newest == null) return null;
  final age = DateTime.now().difference(newest.createdAt).inMilliseconds;
  return ReceiveLatencySample(
    totalMilliseconds: age < 0 ? 0 : age,
    webDavMilliseconds: webDavMilliseconds,
  );
}

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

class ReceiveLatencySample {
  const ReceiveLatencySample({
    required this.totalMilliseconds,
    required this.webDavMilliseconds,
  });

  final int totalMilliseconds;
  final int webDavMilliseconds;
}

class GotifyCoordinatorState {
  const GotifyCoordinatorState({
    this.incomingTransfers = const [],
    this.lastReceivedFile,
    this.lastError,
    this.lastReceipt,
    this.clipboardCopyRevision = 0,
    this.lastTextLatency,
    this.lastFileLatency,
  });

  final List<IncomingTransfer> incomingTransfers;
  final IncomingTransfer? lastReceivedFile;
  final String? lastError;
  final String? lastReceipt;
  final int clipboardCopyRevision;
  final ReceiveLatencySample? lastTextLatency;
  final ReceiveLatencySample? lastFileLatency;

  GotifyCoordinatorState copyWith({
    List<IncomingTransfer>? incomingTransfers,
    IncomingTransfer? lastReceivedFile,
    String? lastError,
    String? lastReceipt,
    int? clipboardCopyRevision,
    ReceiveLatencySample? lastTextLatency,
    ReceiveLatencySample? lastFileLatency,
    bool clearError = false,
  }) {
    return GotifyCoordinatorState(
      incomingTransfers: incomingTransfers ?? this.incomingTransfers,
      lastReceivedFile: lastReceivedFile ?? this.lastReceivedFile,
      lastError: clearError ? null : lastError ?? this.lastError,
      lastReceipt: lastReceipt ?? this.lastReceipt,
      clipboardCopyRevision:
          clipboardCopyRevision ?? this.clipboardCopyRevision,
      lastTextLatency: lastTextLatency ?? this.lastTextLatency,
      lastFileLatency: lastFileLatency ?? this.lastFileLatency,
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
    _ref.listen<bool>(appForegroundProvider, (previous, next) {
      if (next && previous == false) {
        _retryWaitingFiles();
        _gotify.replayPendingEvents();
      } else if (!next && previous == true) {
        _deferPendingTimersForBackground();
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
  Timer? _fileRefreshDebounce;
  final List<RemoteSendEvent> _pendingFileRefreshEvents = [];
  final Set<String> _refreshedFileEventIds = {};
  final Set<String> _downloadedFileEventIds = {};

  void _handleEvent(RemoteSendEvent event) {
    if (_shouldDeferInBackground(event)) {
      unawaited(_gotify.deferEvent(event));
      return;
    }

    final config = _ref.read(configProvider).valueOrNull;
    if (_gotify.isDeferredEvent(event.eventId) &&
        config != null &&
        !config.gotify.isWithinHistoryLookback(event.createdAt)) {
      unawaited(_gotify.acknowledgeEvent(event.eventId));
      return;
    }

    switch (event.type) {
      case RemoteSendEvent.textChanged:
        _scheduleTextRefresh(event);
      case RemoteSendEvent.fileReady:
        _scheduleFileRefresh(event);
        _enqueueFile(event);
      case RemoteSendEvent.fileReceived:
        final fileName = event.payload['fileName'] as String? ?? '';
        state = state.copyWith(
          lastReceipt: '$fileName received by ${event.senderName}',
        );
        unawaited(_gotify.acknowledgeEvent(event.eventId));
    }
  }

  void _deferPendingTimersForBackground() {
    final gotify = _ref.read(configProvider).valueOrNull?.gotify;
    if (gotify == null) return;
    if (!gotify.receiveTextInBackground) {
      _textRefreshDebounce?.cancel();
      for (final event in _pendingTextEvents) {
        unawaited(_gotify.deferEvent(event));
      }
    }
    if (!gotify.receiveFilesInBackground) {
      _fileRefreshDebounce?.cancel();
      for (final event in _pendingFileRefreshEvents) {
        unawaited(_gotify.deferEvent(event));
      }
      final queuedFiles = List<RemoteSendEvent>.from(_fileQueue);
      _fileQueue.clear();
      for (final event in queuedFiles) {
        unawaited(_gotify.deferEvent(event));
        _waitForPolicy(
          event,
          error: 'Waiting for the app to return to foreground',
        );
      }
    }
  }

  bool _shouldDeferInBackground(RemoteSendEvent event) {
    final gotify = _ref.read(configProvider).valueOrNull?.gotify;
    if (gotify == null) return true;
    return shouldDeferRemoteEventInBackground(
      event,
      gotify,
      isForeground: _ref.read(appForegroundProvider),
    );
  }

  void _scheduleTextRefresh(RemoteSendEvent event) {
    final config = _ref.read(configProvider).valueOrNull;
    final serverKey = event.payload['serverKey'] as String? ?? '';
    if (config == null || _matchingServer(config.servers, serverKey) == null) {
      return;
    }

    if (!_pendingTextEvents.any((item) => item.eventId == event.eventId)) {
      _pendingTextEvents.add(event);
    }
    _textRefreshDebounce?.cancel();
    _textRefreshDebounce = Timer(const Duration(milliseconds: 80), () async {
      final pending = List<RemoteSendEvent>.from(_pendingTextEvents);
      _pendingTextEvents.clear();
      final bySource = <(String, String), List<RemoteSendEvent>>{};
      for (final item in pending) {
        final date = item.payload['date'] as String? ?? '';
        final itemServerKey = item.payload['serverKey'] as String? ?? '';
        if (date.isNotEmpty && itemServerKey.isNotEmpty) {
          bySource.putIfAbsent((itemServerKey, date), () => []).add(item);
        }
      }
      final completed = <RemoteSendEvent>[];
      final refreshedTextById = <String, String>{};
      var webDavMilliseconds = 0;
      final autoCopyEnabled =
          _ref.read(configProvider).valueOrNull?.gotify.autoCopyTextEnabled ??
          false;

      for (final entry in bySource.entries) {
        final currentConfig = _ref.read(configProvider).valueOrNull;
        if (currentConfig == null) continue;
        final sourceServer = _matchingServer(
          currentConfig.servers,
          entry.key.$1,
        );
        if (sourceServer == null) continue;

        final activeServer = currentConfig.activeTextServer;
        final updateUi =
            activeServer != null &&
            webDavServerKey(activeServer) == entry.key.$1;
        if (!updateUi && !autoCopyEnabled) {
          completed.addAll(entry.value);
          continue;
        }

        final serviceOverride = updateUi
            ? null
            : (WebDavService()..initializeWithServer(sourceServer));
        final webDavWatch = Stopwatch()..start();
        final messages = await _ref
            .read(messageHistoryProvider.notifier)
            .refreshFromRemoteChange(
              entry.key.$2,
              serviceOverride: serviceOverride,
              updateUi: updateUi,
            );
        webDavMilliseconds += webDavWatch.elapsedMilliseconds;
        if (!mounted) return;
        if (messages == null) continue;
        completed.addAll(entry.value);

        if (autoCopyEnabled) {
          refreshedTextById.addEntries(
            messages.map((message) => MapEntry(message.id, message.content)),
          );
        }
      }

      final clipboardText = autoCopyEnabled
          ? selectNewestTextForClipboard(completed, refreshedTextById)
          : null;
      if (clipboardText != null) {
        try {
          await Clipboard.setData(ClipboardData(text: clipboardText));
          if (!mounted) return;
          state = state.copyWith(
            clipboardCopyRevision: state.clipboardCopyRevision + 1,
          );
        } catch (error) {
          if (mounted) {
            state = state.copyWith(
              lastError: 'Failed to copy new text: $error',
            );
          }
          return;
        }
      }
      final latency = _receiveLatency(completed, webDavMilliseconds);
      if (latency != null) {
        state = state.copyWith(lastTextLatency: latency);
      }
      for (final item in completed) {
        await _gotify.acknowledgeEvent(item.eventId);
      }
    });
  }

  void _scheduleFileRefresh(RemoteSendEvent event) {
    final config = _ref.read(configProvider).valueOrNull;
    final server = config?.activeFilesServer;
    if (server == null ||
        event.payload['serverKey'] != webDavServerKey(server) ||
        _refreshedFileEventIds.contains(event.eventId)) {
      return;
    }

    if (!_pendingFileRefreshEvents.any(
      (item) => item.eventId == event.eventId,
    )) {
      _pendingFileRefreshEvents.add(event);
    }
    _fileRefreshDebounce?.cancel();
    _fileRefreshDebounce = Timer(const Duration(milliseconds: 120), () async {
      final pending = List<RemoteSendEvent>.from(_pendingFileRefreshEvents);
      _pendingFileRefreshEvents.clear();
      final webDavWatch = Stopwatch()..start();
      final success = await _ref.read(fileListProvider.notifier).refresh();
      if (!mounted) return;
      if (!success) {
        state = state.copyWith(
          lastError: 'Failed to refresh the WebDAV file list',
        );
        return;
      }

      final latency = _receiveLatency(pending, webDavWatch.elapsedMilliseconds);
      if (latency != null) {
        state = state.copyWith(lastFileLatency: latency);
      }
      for (final item in pending) {
        _refreshedFileEventIds.add(item.eventId);
        await _acknowledgeFileIfComplete(item);
      }
    });
  }

  Future<void> _acknowledgeFileIfComplete(RemoteSendEvent event) async {
    final config = _ref.read(configProvider).valueOrNull;
    if (config == null) return;
    final serverKey = event.payload['serverKey'] as String? ?? '';
    if (_matchingServer(config.servers, serverKey) == null) return;
    final activeServer = config.activeFilesServer;
    final fileListRefreshRequired =
        activeServer != null && serverKey == webDavServerKey(activeServer);
    if (fileListRefreshRequired &&
        !_refreshedFileEventIds.contains(event.eventId)) {
      return;
    }

    final fileSize = (event.payload['fileSize'] as num?)?.toInt() ?? 0;
    final autoDownloadRequired =
        config.gotify.autoDownloadEnabled &&
        (config.gotify.maxAutoDownloadBytes <= 0 ||
            fileSize <= config.gotify.maxAutoDownloadBytes);
    if (autoDownloadRequired &&
        !_downloadedFileEventIds.contains(event.eventId)) {
      return;
    }

    if (!autoDownloadRequired) {
      _waitingFiles.remove(event.eventId);
      _setTransfer(event.eventId, status: 'available');
    }
    _refreshedFileEventIds.remove(event.eventId);
    _downloadedFileEventIds.remove(event.eventId);
    await _gotify.acknowledgeEvent(event.eventId);
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

    if (!_ref.read(appForegroundProvider) && !gotify.receiveFilesInBackground) {
      await _gotify.deferEvent(event);
      _waitForPolicy(
        event,
        error: 'Waiting for the app to return to foreground',
      );
      return;
    }
    if (!gotify.autoDownloadEnabled) {
      _waitForPolicy(event);
      await _acknowledgeFileIfComplete(event);
      return;
    }
    if (gotify.maxAutoDownloadBytes > 0 &&
        fileSize > gotify.maxAutoDownloadBytes) {
      _waitForPolicy(
        event,
        error: 'File exceeds this device auto-download limit',
      );
      await _acknowledgeFileIfComplete(event);
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
      _downloadedFileEventIds.add(event.eventId);
      await _acknowledgeFileIfComplete(event);
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
    final config = _ref.read(configProvider).valueOrNull;
    if (!_ref.read(appForegroundProvider) &&
        !(config?.gotify.receiveFilesInBackground ?? false)) {
      return;
    }
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
    return availableDownloadPath(p.join(directory.path, fileName));
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
    _fileRefreshDebounce?.cancel();
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
