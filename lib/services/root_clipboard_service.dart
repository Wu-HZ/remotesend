import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/root_clipboard.dart';

/// No shell commands, file paths or arbitrary operations are accepted from Dart.
class RootClipboardService {
  RootClipboardService({
    MethodChannel methods = const MethodChannel('remote_send/root_clipboard'),
    EventChannel events = const EventChannel(
      'remote_send/root_clipboard_events',
    ),
  }) : _methods = methods,
       _events = events;

  static const maxTextBytes = 32 * 1024;
  // Intentionally includes whitespace, a newline and multibyte characters.
  static const probeText = 'RemoteSend clipboard test ✓\n  剪贴板测试  ';
  final MethodChannel _methods;
  final EventChannel _events;

  late final Stream<RootClipboardEvent> events = _events
      .receiveBroadcastStream()
      .map(
        (event) => RootClipboardEvent.fromMap(event as Map<Object?, Object?>),
      );

  Future<RootClipboardInfo> start() async {
    final map = await _methods
        .invokeMapMethod<Object?, Object?>('start')
        .timeout(const Duration(seconds: 65));
    if (map == null) throw const FormatException('Missing bridge identity');
    return RootClipboardInfo.fromMap(map);
  }

  Future<void> stop() => _methods.invokeMethod<void>('stop');

  Future<RootClipboardSnapshot> read() => _snapshot('read');

  Future<RootClipboardSnapshot> writeText(String text) {
    if (text.isEmpty || utf8.encode(text).length > maxTextBytes) {
      throw ArgumentError('Expected nonempty clipboard text up to 32 KiB');
    }
    return _snapshot('write', {'text': text});
  }

  Future<RootClipboardSnapshot> _snapshot(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    final map = await _methods
        .invokeMapMethod<Object?, Object?>(method, args)
        .timeout(const Duration(seconds: 8));
    if (map == null) throw const FormatException('Missing clipboard snapshot');
    final meta = RootClipboardMetadata.fromMap(map);
    final text = map['text'];
    if (meta.kind == RootClipboardKind.text) {
      if (text is! String ||
          text.isEmpty ||
          utf8.encode(text).length > maxTextBytes ||
          meta.bytes != utf8.encode(text).length) {
        throw const FormatException('Invalid clipboard text');
      }
    } else if (text != null) {
      throw const FormatException('Unexpected clipboard body');
    }
    return RootClipboardSnapshot(meta, text as String?);
  }
}
