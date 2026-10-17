import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

enum ClipboardAutoSendError { read, send }

/// An explicitly enabled, non-persistent clipboard forwarding session.
///
/// Polling keeps working when a desktop window loses focus. Clipboard access
/// policy and message transport are injected so this can later be reused by a
/// global listener without tying its lifetime to the text screen.
class ClipboardAutoSendSession extends ChangeNotifier {
  ClipboardAutoSendSession({
    required this.readText,
    required this.sendText,
    required this.canSend,
    required this.canRead,
    required this.isInternalText,
    required this.onError,
    this.interval = const Duration(milliseconds: 500),
  });

  final Future<String?> Function() readText;
  final Future<bool> Function(String) sendText;
  final bool Function() canSend;
  final bool Function() canRead;
  final bool Function(String) isInternalText;
  final void Function(ClipboardAutoSendError) onError;
  final Duration interval;

  final Queue<String> _pending = Queue<String>();
  Timer? _timer;
  String? _lastText;
  int _generation = 0;
  bool _active = false;
  bool _sending = false;
  bool _disposed = false;
  int? _readingGeneration;

  bool get isActive => _active;

  Future<void> start() async {
    if (_disposed || _active) return;
    final generation = ++_generation;
    _active = true;
    notifyListeners();
    try {
      // Establish a baseline: enabling must never send existing clipboard data.
      final baseline = (await readText())?.trim();
      if (!_isCurrent(generation)) return;
      _lastText = baseline;
      _timer = Timer.periodic(interval, (_) => unawaited(_poll(generation)));
    } catch (_) {
      _fail(generation, ClipboardAutoSendError.read);
    }
  }

  void stop() {
    if (!_active) return;
    _active = false;
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    // An upload already handed to the transport may finish, but no queued
    // content or asynchronous clipboard read may start another upload.
    notifyListeners();
  }

  bool _isCurrent(int generation) =>
      !_disposed && _active && generation == _generation;

  Future<void> _poll(int generation) async {
    if (!_isCurrent(generation) ||
        _readingGeneration == generation ||
        !canRead()) {
      return;
    }
    _readingGeneration = generation;
    try {
      final text = (await readText())?.trim();
      if (!_isCurrent(generation)) return;
      if (text != _lastText) {
        _lastText = text;
        if (text != null && text.isNotEmpty && !isInternalText(text)) {
          _pending.add(text);
        }
      }
    } catch (_) {
      _fail(generation, ClipboardAutoSendError.read);
      return;
    } finally {
      if (_readingGeneration == generation) _readingGeneration = null;
    }
    await _drain(generation);
  }

  Future<void> _drain(int generation) async {
    if (_sending) return;
    _sending = true;
    try {
      while (_isCurrent(generation) && _pending.isNotEmpty && canSend()) {
        final text = _pending.removeFirst();
        final success = await sendText(text);
        if (!success) {
          _fail(generation, ClipboardAutoSendError.send);
          return;
        }
      }
    } catch (_) {
      _fail(generation, ClipboardAutoSendError.send);
    } finally {
      _sending = false;
    }
  }

  void _fail(int generation, ClipboardAutoSendError error) {
    if (!_isCurrent(generation)) return;
    stop();
    onError(error);
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}
