import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gotify_models.dart';
import '../models/gotify_text_message.dart';
import '../services/text_clipboard_service.dart';
import 'app_visibility_provider.dart';
import 'config_provider.dart';
import 'gotify_provider.dart';

class GotifyTextSessionState {
  const GotifyTextSessionState({
    this.messages = const [],
    this.pendingCount = 0,
    this.failure,
    this.clipboardCopyRevision = 0,
    this.droppedCount = 0,
  });
  final List<GotifyTextMessage> messages;
  final int pendingCount;
  final RealtimeTextFailure? failure;
  final int clipboardCopyRevision;
  final int droppedCount;
  bool get isSending => pendingCount > 0;
  GotifyTextSessionState copyWith({
    List<GotifyTextMessage>? messages,
    int? pendingCount,
    RealtimeTextFailure? failure,
    bool clearFailure = false,
    int? clipboardCopyRevision,
    int? droppedCount,
  }) => GotifyTextSessionState(
    messages: messages ?? this.messages,
    pendingCount: pendingCount ?? this.pendingCount,
    failure: clearFailure ? null : failure ?? this.failure,
    clipboardCopyRevision: clipboardCopyRevision ?? this.clipboardCopyRevision,
    droppedCount: droppedCount ?? this.droppedCount,
  );
}

final realtimeTextClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final gotifyTextSessionProvider =
    StateNotifierProvider<GotifyTextSessionNotifier, GotifyTextSessionState>((
      ref,
    ) {
      return GotifyTextSessionNotifier(
        ref,
        now: ref.read(realtimeTextClockProvider),
      );
    });

class _TextJob {
  _TextJob(this.event, this.generation, this.identity);
  final RemoteSendEvent event;
  final int generation;
  final Object identity;
  final completer = Completer<bool>();
  int get bytes => utf8.encode(event.payload['content'] as String).length;
}

/// All body-bearing state lives here, never in GotifyRuntimeStore.
class GotifyTextSessionNotifier extends StateNotifier<GotifyTextSessionState> {
  GotifyTextSessionNotifier(this._ref, {required DateTime Function() now})
    : _now = now,
      super(const GotifyTextSessionState()) {
    _ref.listen(gotifyConfigProvider, (previous, next) {
      if (previous != null &&
          (gotifyTextIdentity(previous) != gotifyTextIdentity(next) ||
              (previous.registerAsTextServer && !next.registerAsTextServer) ||
              (previous.enabled && !next.enabled))) {
        _reset();
      } else if (previous != null &&
          !previous.receiveTextInBackground &&
          next.receiveTextInBackground) {
        _flushBackground();
      }
    });
    _ref.listen<bool>(appForegroundProvider, (_, foreground) {
      if (foreground) _flushBackground();
    });
  }

  final Ref _ref;
  final DateTime Function() _now;
  final Queue<_TextJob> _queue = Queue();
  final List<(RemoteSendEvent, DateTime)> _background = [];
  final Set<String> _seen = {};
  _TextJob? _active;
  bool _processing = false;
  bool _copyScheduled = false;
  String? _copyText;
  int _generation = 0;

  GotifyConfig get _config => _ref.read(gotifyConfigProvider);

  Future<bool> send(String content, {String? retryId}) {
    final config = _config;
    final transport = _ref.read(gotifyProvider);
    RealtimeTextFailure? failure;
    if (content.trim().isEmpty) {
      failure = RealtimeTextFailure.empty;
    } else if (utf8.encode(content).length > maxRealtimeTextBytes) {
      failure = RealtimeTextFailure.tooLarge;
    } else if (!config.registerAsTextServer ||
        !config.isConfigured ||
        !transport.isConnected ||
        transport.applicationId == null) {
      failure = RealtimeTextFailure.notReady;
    }
    final queuedBytes =
        _queue.fold<int>(0, (sum, item) => sum + item.bytes) +
        (_active?.bytes ?? 0);
    if (failure == null &&
        (_queue.length + (_active == null ? 0 : 1) >= 100 ||
            queuedBytes + utf8.encode(content).length > 1024 * 1024)) {
      failure = RealtimeTextFailure.queueFull;
    }
    final existing = retryId == null
        ? null
        : state.messages.where((m) => m.id == retryId && m.isLocal).firstOrNull;
    if (retryId != null &&
        (existing == null || existing.status == RealtimeTextStatus.sending)) {
      return Future.value(false);
    }
    final event =
        existing?.event ??
        RemoteSendEvent(
          type: RemoteSendEvent.textDirect,
          senderDeviceId: config.deviceId,
          senderName:
              _ref.read(configProvider).valueOrNull?.localName ?? 'RemoteSend',
          targetDeviceIds: List.of(config.targetDeviceIds),
          payload: {'contentType': 'text/plain', 'content': content},
        );
    if (failure != null) {
      // System-shared text has no composer draft. Keep a bounded failed record
      // so a temporary disconnect never silently loses that text.
      state = state.copyWith(
        failure: failure,
        messages:
            !config.registerAsTextServer ||
                failure == RealtimeTextFailure.empty ||
                failure == RealtimeTextFailure.tooLarge
            ? state.messages
            : _bounded([
                ...state.messages.where((m) => m.id != event.eventId),
                GotifyTextMessage(
                  event: event,
                  isLocal: true,
                  status: RealtimeTextStatus.failed,
                  failure: failure,
                ),
              ]),
      );
      return Future.value(false);
    }
    final job = _TextJob(event, _generation, gotifyTextIdentity(config));
    _queue.add(job);
    final message = GotifyTextMessage(
      event: event,
      isLocal: true,
      status: RealtimeTextStatus.sending,
    );
    state = state.copyWith(
      messages: _bounded([
        ...state.messages.where((m) => m.id != event.eventId),
        message,
      ]),
      pendingCount: state.pendingCount + 1,
      clearFailure: true,
    );
    unawaited(_process());
    return job.completer.future;
  }

  Future<void> _process() async {
    if (_processing) return;
    _processing = true;
    try {
      while (mounted && _queue.isNotEmpty) {
        final job = _queue.removeFirst();
        _active = job;
        var success = false;
        RealtimeTextFailure? failure;
        try {
          if (job.generation != _generation ||
              job.identity != gotifyTextIdentity(_config)) {
            throw const RealtimeTextException(RealtimeTextFailure.notReady);
          }
          await _ref.read(gotifyProvider.notifier).sendRealtimeText(job.event);
          success = true;
        } on RealtimeTextException catch (error) {
          failure = error.failure;
        } catch (_) {
          failure = RealtimeTextFailure.sendFailed;
        }
        if (mounted && job.generation == _generation) {
          state = state.copyWith(
            messages: state.messages
                .map(
                  (m) => m.id == job.event.eventId
                      ? m.withResult(
                          success
                              ? RealtimeTextStatus.sent
                              : failure == RealtimeTextFailure.uncertain
                              ? RealtimeTextStatus.uncertain
                              : RealtimeTextStatus.failed,
                          failure,
                        )
                      : m,
                )
                .toList(),
            pendingCount: _queue.length,
            failure: failure,
          );
        }
        if (!job.completer.isCompleted) {
          job.completer.complete(success && job.generation == _generation);
        }
        _active = null;
      }
    } finally {
      _processing = false;
    }
  }

  void receive(RemoteSendEvent event) {
    if (!mounted ||
        !_config.registerAsTextServer ||
        !_config.isConfigured ||
        !event.isForDevice(_config.deviceId) ||
        !isValidRealtimeText(event) ||
        !_seen.add(event.eventId)) {
      return;
    }
    if (_seen.length > 500) _seen.remove(_seen.first);
    if (!_ref.read(appForegroundProvider) && !_config.receiveTextInBackground) {
      if (_background.length >= 200) {
        _background.removeAt(0);
        state = state.copyWith(droppedCount: state.droppedCount + 1);
      }
      _background.add((event, _now()));
      return;
    }
    _appendReceived(event);
  }

  void _flushBackground() {
    if (!mounted) return;
    final pending = List.of(_background);
    _background.clear();
    final cutoff = _now().subtract(_config.historyLookback);
    for (final (event, receivedAt) in pending) {
      if (receivedAt.isBefore(cutoff) ||
          !_config.registerAsTextServer ||
          !_config.isConfigured) {
        state = state.copyWith(droppedCount: state.droppedCount + 1);
      } else {
        _appendReceived(event);
      }
    }
  }

  void _appendReceived(RemoteSendEvent event) {
    state = state.copyWith(
      messages: _bounded([
        ...state.messages,
        GotifyTextMessage(
          event: event,
          isLocal: false,
          status: RealtimeTextStatus.received,
        ),
      ]),
    );
    if (_config.autoCopyTextEnabled) {
      _copyText = event.payload['content'] as String;
      if (_copyScheduled) return;
      _copyScheduled = true;
      final generation = _generation;
      scheduleMicrotask(() async {
        if (!mounted || generation != _generation) return;
        _copyScheduled = false;
        final text = _copyText;
        _copyText = null;
        if (text == null || !_config.autoCopyTextEnabled) return;
        try {
          await _ref.read(textClipboardServiceProvider).writeText(text);
          if (mounted && generation == _generation) {
            state = state.copyWith(
              clipboardCopyRevision: state.clipboardCopyRevision + 1,
            );
          }
        } catch (_) {
          // Receiving remains successful even when clipboard access is denied.
        }
      });
    }
  }

  List<GotifyTextMessage> _bounded(List<GotifyTextMessage> messages) =>
      messages.length <= 200
      ? messages
      : messages.sublist(messages.length - 200);

  void clearError() {
    state = state.copyWith(clearFailure: true, droppedCount: 0);
  }

  void clear() {
    state = state.copyWith(messages: [], clearFailure: true, droppedCount: 0);
  }

  void _reset() {
    _generation++;
    for (final job in _queue) {
      if (!job.completer.isCompleted) job.completer.complete(false);
    }
    _queue.clear();
    if (_active case final active?) {
      if (!active.completer.isCompleted) active.completer.complete(false);
    }
    _background.clear();
    _seen.clear();
    _copyScheduled = false;
    _copyText = null;
    state = const GotifyTextSessionState();
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }
}
