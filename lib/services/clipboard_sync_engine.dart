import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/clipboard_sync.dart';
import '../models/gotify_models.dart';
import '../models/root_clipboard.dart';
import 'gotify_service.dart';
import 'clipboard_sync_history.dart';

abstract class SyncClipboard {
  Stream<void> get changes;
  bool get eventDriven;
  Future<void> start();
  Future<bool> locked();
  Future<RootClipboardSnapshot> read();
  Future<void> write(String text);
  Future<void> notifyReceived(String deviceName, String text) async {}
  Future<void> stop();
}

class _Peer {
  _Peer(this.session, this.offset, this.seenAt, [this.proof = '']);
  String proof;
  final String session;
  int offset, seenAt, sequence = 0;
}

class _Local {
  _Local(this.text, this.revision, this.at);
  final String text;
  final int revision, at;
}

class _Incoming {
  _Incoming(this.event, this.body, this.order);
  final RemoteSendEvent event;
  final Map<String, dynamic> body;
  final int order;
}

/// Shared by Windows and an Android headless FlutterEngine. History is written
/// separately to an app-private local archive; bodies are never fetched from Gotify.
/// Each receiver run has an unpredictable nonce; fresh challenge ACKs bind peers to it.
class ClipboardSyncEngine {
  static const eventType = 'clipboard_sync';
  ClipboardSyncEngine({
    required this.config,
    required this.clipboard,
    required this.onStatus,
    this.history = const ClipboardSyncHistory(),
    GotifyService Function(GotifyConfig)? transport,
    DateTime Function()? now,
    this.pollInterval = const Duration(milliseconds: 500),
    this.helloInterval = const Duration(seconds: 30),
  }) : _factory = transport ?? GotifyService.new,
       _now = now ?? DateTime.now;
  final ClipboardSyncConfig config;
  final Duration pollInterval, helloInterval;
  final SyncClipboard clipboard;
  final void Function(ClipboardSyncStatus) onStatus;
  final ClipboardSyncHistory history;
  final GotifyService Function(GotifyConfig) _factory;
  final DateTime Function() _now;
  GotifyService? _service;
  StreamSubscription<GotifyMessage>? _messages;
  StreamSubscription<void>? _changes;
  Timer? _pollTimer, _helloTimer, _retry, _probeTimer;
  int _generation = 0,
      _revision = 0,
      _seq = 0,
      _order = 0,
      _sent = 0,
      _received = 0,
      _appId = 0;
  int? _sendingGeneration;
  bool _closed = false,
      _connected = false,
      _reading = false,
      _writing = false,
      _baseline = false,
      _dirty = true,
      _locked = false,
      _receiving = false;
  String? _last, _challenge;
  int _challengeAt = 0, _lastActivity = 0;
  String _session = const Uuid().v4();
  final _peers = <String, _Peer>{};
  final _proofs = <String, (String, int)>{};
  final _introduced = <String, String>{};
  final _acked = <String>{}, _seen = <String>{};
  _Local? _local;
  _Incoming? _incoming;
  GotifyMessage? _nextMessage;
  int get _ms => _now().millisecondsSinceEpoch;
  bool get _sending => _sendingGeneration == _generation;
  Iterable<String> get _live =>
      _peers.keys.where((p) => _ms - _peers[p]!.seenAt < 90000);
  bool _current(int g) => !_closed && g == _generation;
  static bool validText(String? text) =>
      text != null &&
      text.isNotEmpty &&
      !text.contains('\u0000') &&
      utf8.encode(text).length <= 32768;

  Future<void> start() async {
    if (!config.enabled || !config.valid) {
      throw const FormatException('Invalid sync settings');
    }
    try {
      await clipboard.start();
    } catch (_) {
      await stop();
      rethrow;
    }
    if (_closed) return;
    _changes = clipboard.changes.listen(
      (_) {
        _dirty = true;
      },
      onError: (Object _) {
        _emit('error', 'clipboard_unavailable');
        unawaited(stop(report: false));
      },
    );
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
    _helloTimer = Timer.periodic(helloInterval, (_) {
      unawaited(_hello());
      _emit();
    });
    await _connect();
  }

  void _emit([String? phase, String? error]) => onStatus(
    ClipboardSyncStatus(
      phase:
          phase ??
          (!_connected
              ? 'reconnecting'
              : _locked
              ? 'paused'
              : (_live.isEmpty || !_baseline)
              ? 'waiting'
              : 'running'),
      sent: _sent,
      received: _received,
      peers: _live.length,
      error: error,
    ),
  );
  void _rotate() {
    _session = const Uuid().v4();
    _peers.clear();
    _proofs.clear();
    _introduced.clear();
    _probeTimer?.cancel();
    _probeTimer = null;
    _acked.clear();
    _seen.clear();
    _challenge = null;
    _seq = 0;
    _baseline = false;
    _last = null;
    _dirty = true;
    _local = null;
    _incoming = null;
    ++_revision;
  }

  Future<void> _connect() async {
    if (_closed) return;
    final g = ++_generation;
    _connected = false;
    _appId = 0;
    _rotate();
    _emit('connecting');
    final service = _factory(config.gotify);
    _service = service;
    try {
      // Authoritative app ID from an app-token-authenticated POST; no history GET.
      final auth = _control('hello', {
        'challenge': const Uuid().v4(),
      }, config.gotify.targetDeviceIds);
      final response = await _postControl(service, auth);
      if (!_current(g)) return;
      if (response.applicationId <= 0) {
        throw const FormatException('Missing application identity');
      }
      _appId = response.applicationId;
      _order = 0;
      _messages = service.messages.listen(
        (message) {
          if (_current(g) &&
              _connected &&
              message.applicationId == _appId &&
              message.id > 0) {
            final event = RemoteSendEvent.fromGotifyMessage(message);
            if (event == null ||
                event.type != eventType ||
                event.senderDeviceId.isEmpty ||
                !event.isForDevice(config.gotify.deviceId)) {
              return;
            }
            final nextIsData =
                _nextMessage != null &&
                RemoteSendEvent.fromGotifyMessage(
                      _nextMessage!,
                    )?.payload['kind'] ==
                    'clip';
            if (event.payload['kind'] == 'clip' || !nextIsData) {
              _nextMessage = message;
            }
            unawaited(_receive(g));
          }
        },
        onError: (Object _) => _lost(g),
        onDone: () => _lost(g),
      );
      await service.connect();
      if (!_current(g)) return;
      _connected = true;
      _baseline = false;
      _dirty = true;
      await _poll();
      await _hello();
      _emit();
    } catch (_) {
      if (_current(g)) _lost(g);
    }
  }

  void _lost(int g) {
    if (!_current(g)) return;
    ++_generation;
    _connected = false;
    _rotate();
    _nextMessage = null;
    final old = _service;
    _service = null;
    unawaited(_messages?.cancel());
    _messages = null;
    if (old != null) unawaited(old.close().catchError((Object _) {}));
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), () => unawaited(_connect()));
    _emit('reconnecting', 'connection_lost');
  }

  RemoteSendEvent _control(
    String kind,
    Map<String, dynamic> data,
    List<String> targets,
  ) => RemoteSendEvent(
    type: eventType,
    senderDeviceId: config.gotify.deviceId,
    senderName: config.name,
    targetDeviceIds: List.of(targets),
    createdAt: _now(),
    payload: {'version': 1, 'kind': kind, 'session': _session, ...data},
  );
  Future<GotifyMessage> _postControl(
    GotifyService service,
    RemoteSendEvent event,
  ) async {
    final result = await service.send(
      event: event,
      title: 'RemoteSend clipboard',
      message: 'Clipboard sync control',
      priority: -2,
    );
    if (result.id <= 0 ||
        result.applicationId <= 0 ||
        (_appId > 0 && result.applicationId != _appId)) {
      throw const FormatException('Invalid application identity');
    }
    // Best effort: avoid accumulating periodic handshake notifications on Gotify.
    // Never delete unrelated messages or depend on history for delivery.
    unawaited(service.deleteMessage(result.id).catchError((Object _) {}));
    return result;
  }

  Future<void> _hello() async {
    if (!_connected || _closed) return;
    final g = _generation, run = _session;
    _challenge = const Uuid().v4();
    _challengeAt = _ms;
    _acked.clear();
    try {
      final event = _control('hello', {
        'challenge': _challenge,
      }, config.gotify.targetDeviceIds);
      if (_current(g) && run == _session) {
        await _postControl(_service!, event);
      }
    } catch (_) {
      if (_current(g)) _lost(g);
    }
  }

  Future<void> _receive(int g) async {
    if (_receiving) return;
    _receiving = true;
    try {
      while (_current(g) && _nextMessage != null) {
        final message = _nextMessage!;
        _nextMessage = null;
        try {
          await _handle(message, g);
        } catch (_) {
          /* reject malformed/unauthenticated frames, never log bodies */
        }
      }
    } finally {
      _receiving = false;
      if (!_closed && _nextMessage != null) unawaited(_receive(_generation));
    }
  }

  void _resumeGuard() {
    final now = _ms;
    final gap = now - _lastActivity;
    if (_lastActivity != 0 && _connected && (gap > 2000 || gap < -2000)) {
      _rotate();
      unawaited(_hello());
      _emit();
    }
    _lastActivity = now;
  }

  Future<void> _handle(GotifyMessage message, int g) async {
    _resumeGuard();
    final event = RemoteSendEvent.fromGotifyMessage(message);
    if (event == null ||
        event.type != eventType ||
        event.senderDeviceId.isEmpty ||
        !event.isForDevice(config.gotify.deviceId) ||
        _seen.contains(event.eventId)) {
      return;
    }
    final body = event.payload;
    if (body['version'] != 1 || !_current(g)) return;
    final peerSession = body['session'];
    if (peerSession is! String || peerSession.length != 36) return;
    _seen.add(event.eventId);
    if (_seen.length > 512) _seen.remove(_seen.first);
    if (body['kind'] == 'hello') {
      final challenge = body['challenge'];
      if (challenge is! String || challenge.length != 36) return;
      final run = _session;
      if (_peers[event.senderDeviceId]?.session != peerSession &&
          _introduced[event.senderDeviceId] != peerSession) {
        _introduced[event.senderDeviceId] = peerSession;
        _probeTimer ??= Timer(const Duration(milliseconds: 100), () {
          _probeTimer = null;
          if (_current(g) && run == _session) unawaited(_hello());
        });
      }
      final proof = const Uuid().v4();
      _proofs[proof] = (event.senderDeviceId, _ms);
      if (_proofs.length > 64) _proofs.remove(_proofs.keys.first);
      final ack = _control(
        'ack',
        {'challenge': challenge, 'target': peerSession, 'proof': proof},
        [event.senderDeviceId],
      );
      if (_current(g) && run == _session) {
        await _postControl(_service!, ack);
      }
    } else if (body['kind'] == 'ack') {
      if (body['target'] != _session ||
          body['challenge'] != _challenge ||
          body['proof'] is! String ||
          (body['proof'] as String).length != 36 ||
          _ms - _challengeAt > 8000 ||
          !_acked.add(event.senderDeviceId)) {
        return;
      }
      final offset =
          event.createdAt.millisecondsSinceEpoch - ((_ms + _challengeAt) ~/ 2);
      final old = _peers[event.senderDeviceId];
      if (old?.session == peerSession) {
        old!.offset = offset;
        old.seenAt = _ms;
        old.proof = body['proof'] as String? ?? '';
      } else {
        _peers[event.senderDeviceId] = _Peer(
          peerSession,
          offset,
          _ms,
          body['proof'] as String? ?? '',
        );
      }
      _emit();
    } else if (body['kind'] == 'clip' && !_locked) {
      var peer = _peers[event.senderDeviceId];
      final targets = body['targets'];
      // Complete the reciprocal handshake with a fresh proof from our ACK,
      // rather than dropping first data until our next heartbeat.
      final proofs = body['proofs'];
      if ((peer == null || peer.session != peerSession) &&
          targets is Map &&
          targets[config.gotify.deviceId] == _session &&
          proofs is Map) {
        final issued = _proofs[proofs[config.gotify.deviceId]];
        if (issued != null &&
            issued.$1 == event.senderDeviceId &&
            _ms - issued.$2 <= 8000) {
          peer = _Peer(
            peerSession,
            event.createdAt.millisecondsSinceEpoch - ((_ms + issued.$2) ~/ 2),
            _ms,
          );
          _peers[event.senderDeviceId] = peer;
          _emit();
        }
      }
      final seq = body['seq'];
      if (peer == null ||
          peer.session != peerSession ||
          targets is! Map ||
          targets[config.gotify.deviceId] != _session ||
          seq is! int ||
          seq <= peer.sequence ||
          !validText(body['text'] as String?) ||
          body['at'] is! int ||
          !_fresh(event, peer, at: body['at'] as int)) {
        return;
      }
      peer.sequence = seq;
      if (message.id <= _order) return;
      if (_incoming == null || message.id > _incoming!.order) {
        _incoming = _Incoming(event, body, message.id);
      }
      await _apply();
    }
  }

  bool _fresh(RemoteSendEvent event, _Peer peer, {int? at}) {
    final age =
        _ms + peer.offset - (at ?? event.createdAt.millisecondsSinceEpoch);
    return age >= -5000 && age <= 15000 && _ms - peer.seenAt < 90000;
  }

  Future<void> _poll() async {
    if (!_closed) _resumeGuard();
    if (_closed || _reading || _writing) return;
    _reading = true;
    final g = _generation;
    try {
      final locked = await clipboard.locked();
      if (!_current(g)) return;
      if (locked != _locked) {
        _locked = locked;
        _rotate();
        if (_connected) unawaited(_hello());
        _emit();
      }
      if (locked || (!_dirty && clipboard.eventDriven)) return;
      _dirty = false;
      final snapshot = await clipboard.read();
      if (_current(g)) _observe(snapshot);
    } catch (_) {
      if (_current(g)) _emit(null, 'clipboard_read');
    } finally {
      _reading = false;
    }
    if (_current(g)) {
      unawaited(_flush());
      unawaited(_apply());
    }
  }

  void _observe(RootClipboardSnapshot snapshot) {
    final text = snapshot.metadata.kind == RootClipboardKind.text
        ? snapshot.text
        : null;
    if (!_baseline || !_connected) {
      _last = text;
      _baseline = _connected;
      if (_baseline) _emit();
      return;
    }
    if (text == _last) return;
    _last = text;
    ++_revision;
    _incoming = null;
    _local = null;
    if (!snapshot.metadata.internal && validText(text) && _live.isNotEmpty) {
      _local = _Local(text!, _revision, _ms);
    }
  }

  Future<void> _flush() async {
    if (_closed || !_connected || _sending || _locked) return;
    final g = _generation;
    _sendingGeneration = g;
    try {
      while (_current(g) && _local != null) {
        final value = _local!;
        _local = null;
        final run = _session;
        final targets = {for (final id in _live) id: _peers[id]!.session};
        if (targets.isEmpty || _ms - value.at > 15000) continue;
        final event = _control('clip', {
          'targets': targets,
          'proofs': {for (final id in targets.keys) id: _peers[id]!.proof},
          'seq': ++_seq,
          'text': value.text,
          'at': value.at,
        }, targets.keys.toList());
        if (!_current(g) ||
            run != _session ||
            value.revision != _revision ||
            _locked) {
          continue;
        }
        final response = await _service!.send(
          event: event,
          title: 'RemoteSend clipboard',
          message: 'Clipboard sync text',
          priority: -2,
        );
        if (!_current(g)) return;
        if (response.applicationId != _appId || response.id <= 0) {
          throw const FormatException('Invalid application identity');
        }
        _order = max(_order, response.id);
        _sent++;
        unawaited(
          _service!.deleteMessage(response.id).catchError((Object _) {}),
        );
        unawaited(
          history
              .record(
                eventId: event.eventId,
                at: _now(),
                direction: 'sent',
                deviceName: config.name,
                text: value.text,
              )
              .catchError((Object _) {}),
        );
        _emit();
      }
    } catch (_) {
      if (_current(g)) _lost(g);
    } finally {
      if (_sendingGeneration == g) _sendingGeneration = null;
    }
    if (_current(g)) unawaited(_apply());
  }

  Future<void> _apply() async {
    if (!_closed) _resumeGuard();
    if (_closed ||
        !_connected ||
        _reading ||
        _writing ||
        _sending ||
        _local != null ||
        _incoming == null ||
        !_baseline) {
      return;
    }
    _writing = true;
    final g = _generation;
    try {
      if (await clipboard.locked()) {
        _locked = true;
        _rotate();
        _emit();
        return;
      }
      final snapshot = await clipboard.read();
      if (!_current(g)) return;
      if (snapshot.metadata.kind == RootClipboardKind.sensitive) {
        _incoming = null;
        return;
      }
      // Detect a local copy that happened between polling ticks before overwriting it.
      _observe(snapshot);
      final value = _incoming;
      if (value == null || _local != null || _sending) return;
      _incoming = null;
      final peer = _peers[value.event.senderDeviceId];
      if (peer == null ||
          peer.session != value.body['session'] ||
          !_fresh(value.event, peer, at: value.body['at'] as int) ||
          (value.body['targets'] as Map)[config.gotify.deviceId] != _session ||
          value.order <= _order) {
        return;
      }
      final text = value.body['text'] as String;
      _last = text;
      ++_revision;
      await clipboard.write(text);
      if (!_current(g)) return;
      await clipboard.notifyReceived(value.event.senderName, text);
      if (!_current(g)) return;
      _order = value.order;
      _received++;
      _dirty = true;
      unawaited(
        history
            .record(
              eventId: value.event.eventId,
              at: _now(),
              direction: 'received',
              deviceName: value.event.senderName,
              text: text,
            )
            .catchError((Object _) {}),
      );
      _emit();
    } catch (_) {
      if (_current(g)) {
        _baseline = false;
        _dirty = true;
        _emit(null, 'clipboard_write');
      }
    } finally {
      _writing = false;
    }
    if (_current(g) && _local != null) unawaited(_flush());
  }

  Future<void> stop({bool report = true}) async {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _pollTimer?.cancel();
    _helloTimer?.cancel();
    _retry?.cancel();
    _probeTimer?.cancel();
    _local = null;
    _incoming = null;
    _nextMessage = null;
    _last = null;
    _peers.clear();
    await _changes?.cancel();
    await _messages?.cancel();
    try {
      await _service?.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* clipboard shutdown still runs */
    }
    await clipboard.stop();
    if (report) _emit('stopped');
  }
}
