import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gotify_models.dart';
import '../models/server_config.dart';
import '../services/gotify_runtime_store.dart';
import '../services/gotify_service.dart';
import 'app_visibility_provider.dart';
import 'config_provider.dart';

enum GotifyConnectionStatus {
  disabled,
  connecting,
  connected,
  reconnecting,
  error,
}

class GotifyState {
  const GotifyState({
    this.status = GotifyConnectionStatus.disabled,
    this.devices = const {},
    this.lastMessageId = 0,
    this.outboxCount = 0,
    this.error,
  });

  final GotifyConnectionStatus status;
  final Map<String, RemoteDevice> devices;
  final int lastMessageId;
  final int outboxCount;
  final String? error;

  bool get isConnected => status == GotifyConnectionStatus.connected;

  List<RemoteDevice> get sortedDevices {
    final result = devices.values.toList();
    result.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return result;
  }

  GotifyState copyWith({
    GotifyConnectionStatus? status,
    Map<String, RemoteDevice>? devices,
    int? lastMessageId,
    int? outboxCount,
    String? error,
    bool clearError = false,
  }) {
    return GotifyState(
      status: status ?? this.status,
      devices: devices ?? this.devices,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      outboxCount: outboxCount ?? this.outboxCount,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// Maintains one Gotify WebSocket while the app is running. WebDAV is never
/// polled here; reconnect history is accepted only inside the configured short
/// lookback window, and older events are discarded.
class GotifyNotifier extends StateNotifier<GotifyState> {
  GotifyNotifier(this._config, this._ref)
    : _store = GotifyRuntimeStore(_runtimeNamespace(_config)),
      super(
        GotifyState(
          status: _config.isConfigured
              ? GotifyConnectionStatus.connecting
              : GotifyConnectionStatus.disabled,
        ),
      ) {
    _ref.listen(configProvider, (previous, next) {
      final previousName = previous?.valueOrNull?.localName;
      final nextName = next.valueOrNull?.localName;
      if (state.isConnected &&
          previousName != null &&
          nextName != null &&
          previousName != nextName) {
        unawaited(_announceDevice());
      }
    });
    Future.microtask(start);
  }

  final GotifyConfig _config;
  final Ref _ref;
  final GotifyRuntimeStore _store;
  final StreamController<RemoteSendEvent> _events =
      StreamController<RemoteSendEvent>.broadcast();

  GotifyRuntimeData _runtime = const GotifyRuntimeData();
  GotifyService? _service;
  StreamSubscription<GotifyMessage>? _messageSubscription;
  Timer? _reconnectTimer;
  final List<GotifyMessage> _catchUpBuffer = [];
  bool _catchingUp = false;
  bool _opening = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  Future<void> _outboundChain = Future<void>.value();

  Stream<RemoteSendEvent> get events => _events.stream;

  Future<void> start() async {
    if (_disposed || !_config.isConfigured) {
      state = state.copyWith(status: GotifyConnectionStatus.disabled);
      return;
    }

    final loadedRuntime = await _store.load();
    final recentDeferred = loadedRuntime.deferredInboundEvents
        .where(
          (event) => _currentConfig.isWithinHistoryLookback(event.createdAt),
        )
        .toList();
    _runtime = loadedRuntime.copyWith(deferredInboundEvents: recentDeferred);
    if (recentDeferred.length != loadedRuntime.deferredInboundEvents.length) {
      await _saveRuntime();
    }
    if (_disposed) return;
    state = state.copyWith(
      devices: _withoutThisDevice(_runtime.devices, _config.deviceId),
      lastMessageId: _runtime.lastMessageId,
      outboxCount: _runtime.outbox.length,
    );
    replayPendingEvents();
    await _openConnection();
  }

  Future<void> _openConnection() async {
    if (_disposed || _opening || !_config.isConfigured) return;
    _opening = true;
    _reconnectTimer?.cancel();
    _catchingUp = true;
    _catchUpBuffer.clear();

    await _closeService();
    final service = GotifyService(_config);
    _service = service;
    _messageSubscription = service.messages.listen(
      (message) {
        if (_catchingUp) {
          _catchUpBuffer.add(message);
        } else {
          _processMessage(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _scheduleReconnect(error.toString());
      },
      onDone: () => _scheduleReconnect('Gotify connection closed'),
      cancelOnError: true,
    );

    try {
      state = state.copyWith(
        status: _reconnectAttempt == 0
            ? GotifyConnectionStatus.connecting
            : GotifyConnectionStatus.reconnecting,
        clearError: true,
      );
      await service.connect();
      if (_disposed || service != _service) return;

      final baseline = _runtime.lastMessageId;
      final historyCutoff = DateTime.now().subtract(
        _currentConfig.historyLookback,
      );
      final fetched = await _fetchMessagesNewerThan(
        baseline,
        notBefore: historyCutoff,
        maxPages: 20,
      );
      fetched.sort((a, b) => a.id.compareTo(b.id));
      for (final message in fetched) {
        await _processMessage(
          message,
          notBefore: historyCutoff,
          persist: false,
        );
      }

      final bufferedById = <int, GotifyMessage>{
        for (final message in _catchUpBuffer) message.id: message,
      };
      final buffered = bufferedById.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      _catchUpBuffer.clear();
      for (final message in buffered) {
        await _processMessage(
          message,
          notBefore: historyCutoff,
          persist: false,
        );
      }

      await _saveRuntime();
      _catchingUp = false;
      _reconnectAttempt = 0;
      state = state.copyWith(
        status: GotifyConnectionStatus.connected,
        clearError: true,
      );
      replayPendingEvents();

      await _announceDevice();
      await _flushOutbox();
    } catch (error) {
      _catchingUp = false;
      _scheduleReconnect(error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<List<GotifyMessage>> _fetchMessagesNewerThan(
    int baseline, {
    required DateTime notBefore,
    required int maxPages,
  }) async {
    final service = _service;
    if (service == null) return const [];

    final result = <GotifyMessage>[];
    int? since;
    for (var pageNumber = 0; pageNumber < maxPages; pageNumber++) {
      final page = await service.fetchMessages(since: since);
      if (page.messages.isEmpty) break;

      var reachedBaseline = false;
      var reachedLookbackBoundary = false;
      for (final message in page.messages) {
        if (message.id > baseline) {
          result.add(message);
        } else {
          reachedBaseline = true;
        }
        if (message.date.isBefore(notBefore)) {
          reachedLookbackBoundary = true;
        }
      }
      if (reachedBaseline ||
          reachedLookbackBoundary ||
          page.nextSince == null) {
        break;
      }
      since = page.nextSince;
    }
    return result;
  }

  Future<void> _processMessage(
    GotifyMessage message, {
    DateTime? notBefore,
    bool persist = true,
  }) async {
    final event = RemoteSendEvent.fromGotifyMessage(message);
    final historyCutoff =
        notBefore ?? DateTime.now().subtract(_currentConfig.historyLookback);
    final deliver = event == null || !event.createdAt.isBefore(historyCutoff);
    var devices = _runtime.devices;
    var processedIds = _runtime.processedEventIds;
    var pendingInbound = _runtime.pendingInboundEvents;
    var deferredInbound = _runtime.deferredInboundEvents;
    RemoteSendEvent? eventToDeliver;

    final alreadyPending =
        event != null &&
        pendingInbound.any((item) => item.eventId == event.eventId);
    final alreadyDeferred =
        event != null &&
        _runtime.deferredInboundEvents.any(
          (item) => item.eventId == event.eventId,
        );
    if (event != null &&
        !processedIds.contains(event.eventId) &&
        !alreadyPending &&
        !alreadyDeferred) {
      if (event.type == RemoteSendEvent.deviceAnnounce) {
        if (deliver && event.senderDeviceId != _config.deviceId) {
          final updated = Map<String, RemoteDevice>.from(devices);
          updated[event.senderDeviceId] = RemoteDevice(
            id: event.senderDeviceId,
            name: event.senderName,
            platform: event.payload['platform'] as String? ?? 'unknown',
            lastSeen: event.createdAt,
          );
          devices = updated;
        }
        processedIds = _appendProcessed(processedIds, event.eventId);
      } else if (!deliver ||
          !event.isForDevice(_config.deviceId) ||
          !_isActionableEvent(event.type)) {
        processedIds = _appendProcessed(processedIds, event.eventId);
      } else {
        pendingInbound = [...pendingInbound, event];
        if (shouldDeferRemoteEventInBackground(
          event,
          _currentConfig,
          isForeground: _ref.read(appForegroundProvider),
        )) {
          deferredInbound = [...deferredInbound, event];
        }
        if (!_catchingUp) eventToDeliver = event;
      }
    }

    _runtime = _runtime.copyWith(
      lastMessageId: message.id > _runtime.lastMessageId
          ? message.id
          : _runtime.lastMessageId,
      devices: devices,
      processedEventIds: processedIds,
      pendingInboundEvents: pendingInbound,
      deferredInboundEvents: deferredInbound,
    );
    state = state.copyWith(
      devices: _withoutThisDevice(devices, _config.deviceId),
      lastMessageId: _runtime.lastMessageId,
    );
    if (persist) await _saveRuntime();
    if (eventToDeliver != null) _events.add(eventToDeliver);
  }

  /// Re-emits active and intentionally deferred inbound notifications.
  void replayPendingEvents() {
    if (_disposed) return;
    final byId = <String, RemoteSendEvent>{
      for (final event in _runtime.pendingInboundEvents) event.eventId: event,
      for (final event in _runtime.deferredInboundEvents) event.eventId: event,
    };
    for (final event in byId.values) {
      if (event.isForDevice(_config.deviceId)) _events.add(event);
    }
  }

  bool isDeferredEvent(String eventId) {
    return _runtime.deferredInboundEvents.any(
      (event) => event.eventId == eventId,
    );
  }

  Future<void> deferEvent(RemoteSendEvent event) async {
    if (_disposed || isDeferredEvent(event.eventId)) return;
    _runtime = _runtime.copyWith(
      deferredInboundEvents: [..._runtime.deferredInboundEvents, event],
    );
    await _saveRuntime();
  }

  /// Marks an inbound event complete only after its one-shot action succeeds.
  /// Active work is session-only; deferred background events survive restart.
  Future<void> acknowledgeEvent(String eventId) async {
    if (_disposed) return;
    final wasPending = _runtime.pendingInboundEvents.any(
      (event) => event.eventId == eventId,
    );
    final wasDeferred = isDeferredEvent(eventId);
    if (!wasPending && !wasDeferred) return;

    _runtime = _runtime.copyWith(
      pendingInboundEvents: _runtime.pendingInboundEvents
          .where((event) => event.eventId != eventId)
          .toList(),
      deferredInboundEvents: _runtime.deferredInboundEvents
          .where((event) => event.eventId != eventId)
          .toList(),
      processedEventIds: _appendProcessed(_runtime.processedEventIds, eventId),
    );
    await _saveRuntime();
  }

  static bool _isActionableEvent(String type) {
    return type == RemoteSendEvent.textChanged ||
        type == RemoteSendEvent.fileReady ||
        type == RemoteSendEvent.fileReceived;
  }

  static List<String> _appendProcessed(List<String> ids, String eventId) {
    final updated = [...ids, eventId];
    return updated.length <= 500
        ? updated
        : updated.sublist(updated.length - 500);
  }

  Future<bool> publishTextChanged({
    required ServerConfig server,
    required String date,
    String? newMessageId,
  }) {
    return _publish(
      RemoteSendEvent(
        type: RemoteSendEvent.textChanged,
        senderDeviceId: _config.deviceId,
        senderName: _localName,
        targetDeviceIds: _currentConfig.targetDeviceIds,
        payload: {
          'date': date,
          'serverKey': webDavServerKey(server),
          if (newMessageId != null)
            RemoteSendEvent.newMessageIdPayloadKey: newMessageId,
        },
      ),
      title: 'RemoteSend · $_localName',
      message: 'New text is available',
      priority: 1,
    );
  }

  Future<bool> publishFileReady({
    required ServerConfig server,
    required String remotePath,
    required String fileName,
    required int fileSize,
  }) {
    return _publish(
      RemoteSendEvent(
        type: RemoteSendEvent.fileReady,
        senderDeviceId: _config.deviceId,
        senderName: _localName,
        targetDeviceIds: _currentConfig.targetDeviceIds,
        payload: {
          'serverKey': webDavServerKey(server),
          'remotePath': remotePath,
          'fileName': fileName,
          'fileSize': fileSize,
        },
      ),
      title: 'RemoteSend · $_localName',
      message: 'File ready: $fileName',
      priority: 3,
    );
  }

  Future<bool> publishFileReceived(RemoteSendEvent source) {
    return _publish(
      RemoteSendEvent(
        type: RemoteSendEvent.fileReceived,
        senderDeviceId: _config.deviceId,
        senderName: _localName,
        targetDeviceIds: [source.senderDeviceId],
        payload: {
          'transferId': source.eventId,
          'fileName': source.payload['fileName'],
        },
      ),
      title: 'RemoteSend · $_localName',
      message: 'File received: ${source.payload['fileName'] ?? ''}',
      priority: 0,
    );
  }

  Future<bool> _publish(
    RemoteSendEvent event, {
    required String title,
    required String message,
    required int priority,
  }) {
    final result = Completer<bool>();
    _outboundChain = _outboundChain.catchError((_) {}).then((_) async {
      final sent = await _publishNow(
        event,
        title: title,
        message: message,
        priority: priority,
      );
      if (sent) await _flushOutboxNow();
      result.complete(sent);
    });
    return result.future;
  }

  Future<bool> _publishNow(
    RemoteSendEvent event, {
    required String title,
    required String message,
    required int priority,
  }) async {
    if (!_config.isConfigured) return false;

    final pending = PendingGotifyEvent(
      event: event,
      title: title,
      message: message,
      priority: priority,
    );
    if (!_runtime.outbox.any((item) => item.event.eventId == event.eventId)) {
      final outbox = event.type == RemoteSendEvent.deviceAnnounce
          ? _runtime.outbox
                .where(
                  (item) =>
                      item.event.type != RemoteSendEvent.deviceAnnounce ||
                      item.event.senderDeviceId != event.senderDeviceId,
                )
                .toList()
          : List<PendingGotifyEvent>.from(_runtime.outbox);
      outbox.add(pending);
      _runtime = _runtime.copyWith(outbox: outbox);
      state = state.copyWith(outboxCount: _runtime.outbox.length);
      await _saveRuntime();
    }

    final service = _service;
    if (service == null || !state.isConnected) return false;

    try {
      await service.send(
        event: event,
        title: title,
        message: message,
        priority: priority,
      );
      final remaining = _runtime.outbox
          .where((item) => item.event.eventId != event.eventId)
          .toList();
      _runtime = _runtime.copyWith(outbox: remaining);
      state = state.copyWith(outboxCount: remaining.length);
      await _saveRuntime();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _flushOutbox() {
    final result = Completer<void>();
    _outboundChain = _outboundChain.catchError((_) {}).then((_) async {
      await _flushOutboxNow();
      result.complete();
    });
    return result.future;
  }

  Future<void> _flushOutboxNow() async {
    final service = _service;
    if (service == null || !state.isConnected || _runtime.outbox.isEmpty) {
      return;
    }

    final snapshot = List<PendingGotifyEvent>.from(_runtime.outbox);
    final remaining = <PendingGotifyEvent>[];
    for (final pending in snapshot) {
      try {
        await service.send(
          event: pending.event,
          title: pending.title,
          message: pending.message,
          priority: pending.priority,
        );
      } catch (_) {
        remaining.add(pending);
      }
    }
    final snapshotIds = snapshot.map((item) => item.event.eventId).toSet();
    final addedWhileSending = _runtime.outbox
        .where((item) => !snapshotIds.contains(item.event.eventId))
        .toList();
    final updatedOutbox = [...remaining, ...addedWhileSending];
    _runtime = _runtime.copyWith(outbox: updatedOutbox);
    state = state.copyWith(outboxCount: updatedOutbox.length);
    await _saveRuntime();
  }

  Future<void> _announceDevice() async {
    await _publish(
      RemoteSendEvent(
        type: RemoteSendEvent.deviceAnnounce,
        senderDeviceId: _config.deviceId,
        senderName: _localName,
        payload: {'platform': Platform.operatingSystem},
      ),
      title: 'RemoteSend device',
      message: '$_localName is online',
      priority: -2,
    );
  }

  GotifyConfig get _currentConfig => _ref.read(gotifyConfigProvider);

  String get _localName =>
      _ref.read(configProvider).valueOrNull?.localName ?? 'RemoteSend';

  void _scheduleReconnect(String error) {
    if (_disposed ||
        !_config.isConfigured ||
        _reconnectTimer?.isActive == true) {
      return;
    }

    _catchingUp = false;
    _opening = false;
    _reconnectAttempt++;
    final exponent = (_reconnectAttempt - 1).clamp(0, 5).toInt();
    final seconds = (1 << exponent).clamp(1, 30).toInt();
    state = state.copyWith(
      status: GotifyConnectionStatus.reconnecting,
      error: error,
    );
    _reconnectTimer = Timer(Duration(seconds: seconds), _openConnection);
  }

  Future<void> _saveRuntime() async {
    try {
      await _store.save(_runtime);
    } catch (_) {
      // Keep operating in memory if local persistence is temporarily unavailable.
    }
  }

  Future<void> _closeService() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    final service = _service;
    _service = null;
    await service?.close();
  }

  static Map<String, RemoteDevice> _withoutThisDevice(
    Map<String, RemoteDevice> devices,
    String ownId,
  ) {
    if (!devices.containsKey(ownId)) return devices;
    final result = Map<String, RemoteDevice>.from(devices)..remove(ownId);
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(_closeService());
    unawaited(_events.close());
    super.dispose();
  }
}

final _gotifyConnectionIdentityProvider = Provider((ref) {
  final config = ref.watch(gotifyConfigProvider);
  return (
    config.enabled,
    config.serverUrl,
    config.appToken,
    config.clientToken,
    config.deviceId,
  );
});

final gotifyProvider = StateNotifierProvider<GotifyNotifier, GotifyState>((
  ref,
) {
  ref.watch(_gotifyConnectionIdentityProvider);
  return GotifyNotifier(ref.read(gotifyConfigProvider), ref);
});

String _runtimeNamespace(GotifyConfig config) {
  final value = '${config.serverUrl.trim()}\n${config.clientToken.trim()}';
  return sha256.convert(value.codeUnits).toString().substring(0, 20);
}
