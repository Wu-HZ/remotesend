import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/root_clipboard.dart';
import '../services/root_clipboard_service.dart';

final rootClipboardSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);
final rootClipboardServiceProvider = Provider((ref) => RootClipboardService());
final rootClipboardDiagnosticsProvider =
    StateNotifierProvider.autoDispose<
      RootClipboardDiagnostics,
      RootClipboardDiagnosticsState
    >((ref) {
      return RootClipboardDiagnostics(ref.read(rootClipboardServiceProvider));
    });

class RootClipboardDiagnosticsState {
  const RootClipboardDiagnosticsState({
    this.info,
    this.busy = false,
    this.changes = 0,
    this.last,
    this.errorCode,
    this.probeMatched,
  });
  final RootClipboardInfo? info;
  final bool busy;
  final int changes;
  final RootClipboardMetadata? last;
  final String? errorCode;
  final bool? probeMatched;
  bool get connected => info != null;

  RootClipboardDiagnosticsState copyWith({
    bool? busy,
    int? changes,
    RootClipboardMetadata? last,
    String? errorCode,
    bool clearError = false,
    bool? probeMatched,
  }) => RootClipboardDiagnosticsState(
    info: info,
    busy: busy ?? this.busy,
    changes: changes ?? this.changes,
    last: last ?? this.last,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
    probeMatched: probeMatched ?? this.probeMatched,
  );
}

/// Diagnostic state contains no clipboard bodies and has no persistence/network dependencies.
class RootClipboardDiagnostics
    extends StateNotifier<RootClipboardDiagnosticsState> {
  RootClipboardDiagnostics(this._service)
    : super(const RootClipboardDiagnosticsState()) {
    _subscription = _service.events.listen(
      _event,
      onError: (Object _) => _streamFailed(),
    );
  }
  final RootClipboardService _service;
  late final StreamSubscription<RootClipboardEvent> _subscription;
  int _generation = 0;

  Future<void> start() async {
    if (state.busy || state.connected) return;
    final token = ++_generation;
    state = const RootClipboardDiagnosticsState(busy: true);
    try {
      final info = await _service.start();
      if (!mounted || token != _generation) return;
      state = RootClipboardDiagnosticsState(info: info);
    } catch (error) {
      if (!mounted || token != _generation) return;
      state = RootClipboardDiagnosticsState(errorCode: _error(error));
      _stopQuietly();
    }
  }

  Future<void> stop() async {
    final token = ++_generation;
    state = const RootClipboardDiagnosticsState(busy: true);
    try {
      await _service.stop();
      if (mounted && token == _generation) {
        state = const RootClipboardDiagnosticsState();
      }
    } catch (error) {
      if (mounted && token == _generation) {
        state = RootClipboardDiagnosticsState(errorCode: _error(error));
      }
    }
  }

  Future<void> read() => _inspect(false);
  Future<void> writeProbe() => _inspect(true);

  Future<void> _inspect(bool probe) async {
    if (!state.connected || state.busy) return;
    final token = _generation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final snapshot = probe
          ? await _service.writeText(RootClipboardService.probeText)
          : await _service.read();
      if (!mounted || token != _generation) return;
      state = state.copyWith(
        busy: false,
        last: snapshot.metadata,
        probeMatched: probe
            ? snapshot.text == RootClipboardService.probeText
            : null,
      );
    } catch (error) {
      if (!mounted || token != _generation) return;
      state = state.copyWith(busy: false, errorCode: _error(error));
    }
  }

  void _event(RootClipboardEvent event) {
    if (!mounted || event.session != state.info?.session) return;
    if (event.stopped) {
      ++_generation;
      state = RootClipboardDiagnosticsState(
        errorCode: event.errorCode == 'stopped'
            ? null
            : _safeCode(event.errorCode),
      );
    } else if (event.metadata != null) {
      state = state.copyWith(changes: state.changes + 1, last: event.metadata);
    } else {
      state = state.copyWith(errorCode: _safeCode(event.errorCode));
    }
  }

  void _streamFailed() {
    if (!mounted) return;
    ++_generation;
    final active = state.connected || state.busy;
    state = const RootClipboardDiagnosticsState(errorCode: 'bridge_failed');
    if (active) _stopQuietly();
  }

  String _error(Object error) => error is PlatformException
      ? _safeCode(error.code)
      : error is TimeoutException
      ? 'request_timeout'
      : 'bridge_failed';

  String _safeCode(String? code) =>
      const {
        'permission_denied',
        'wrong_identity',
        'unsupported_api',
        'root_unavailable',
        'startup_timeout',
        'request_timeout',
        'disconnected',
        'not_connected',
        'invalid_response',
        'invalid_request',
        'busy',
        'stopped',
      }.contains(code)
      ? code!
      : 'bridge_failed';

  void _stopQuietly() => unawaited(_service.stop().catchError((Object _) {}));

  @override
  void dispose() {
    ++_generation;
    unawaited(_subscription.cancel().catchError((Object _) {}));
    _stopQuietly();
    super.dispose();
  }
}
