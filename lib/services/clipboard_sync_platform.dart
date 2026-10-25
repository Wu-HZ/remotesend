import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/clipboard_sync.dart';
import '../models/root_clipboard.dart';
import 'clipboard_sync_engine.dart';
import 'root_clipboard_service.dart';

class ClipboardSyncPlatform {
  const ClipboardSyncPlatform();
  static const methods = MethodChannel('remote_send/clipboard_sync');
  static const events = EventChannel('remote_send/clipboard_sync_events');
  Future<ClipboardSyncConfig?> load() async {
    final value = await methods.invokeMethod<String>('load');
    return value == null
        ? null
        : ClipboardSyncConfig.fromJson(
            Map<String, dynamic>.from(jsonDecode(value) as Map),
          );
  }

  Future<void> save(ClipboardSyncConfig value) =>
      methods.invokeMethod<void>('save', {'value': jsonEncode(value.toJson())});
  Future<void> startAndroid() => methods.invokeMethod<void>('start');
  Future<void> stopAndroid() => methods.invokeMethod<void>('stop');
  Future<void> abortAndroid() => methods.invokeMethod<void>('abort');
  Future<void> report(ClipboardSyncStatus status) =>
      methods.invokeMethod<void>('report', status.toJson());
  Future<bool> locked() async =>
      await methods.invokeMethod<bool>('locked') ?? true;
  Future<ClipboardSyncStatus> status() async => ClipboardSyncStatus.fromJson(
    await methods.invokeMapMethod<Object?, Object?>('status') ?? {},
  );
  Stream<ClipboardSyncStatus> get statuses =>
      events.receiveBroadcastStream().map(
        (value) => ClipboardSyncStatus.fromJson(value as Map<Object?, Object?>),
      );
}

class PlatformSyncClipboard implements SyncClipboard {
  PlatformSyncClipboard({
    RootClipboardService? root,
    ClipboardSyncPlatform platform = const ClipboardSyncPlatform(),
    bool? android,
    String Function()? locale,
  }) : _android = android ?? Platform.isAndroid,
       _locale = locale ?? (() => 'system'),
       _root = root ?? RootClipboardService(),
       _platform = platform;
  final bool _android;
  final String Function() _locale;
  int? _lockEpoch;
  final RootClipboardService _root;
  final ClipboardSyncPlatform _platform;
  @override
  bool get eventDriven => _android;
  @override
  Stream<void> get changes => !_android
      ? const Stream.empty()
      : _root.events.map((event) {
          if (event.stopped || event.errorCode != null) {
            throw StateError('Clipboard bridge unavailable');
          }
        });
  @override
  Future<void> start() async {
    if (_android) await _root.start();
  }

  @override
  Future<bool> locked() async {
    if (_android) {
      final epoch = await ClipboardSyncPlatform.methods.invokeMethod<int>(
        'lockEpoch',
      );
      final changed = _lockEpoch != null && epoch != _lockEpoch;
      _lockEpoch = epoch;
      // A missed lock/unlock while Dart slept must still rotate the receiver nonce.
      if (changed) return true;
    }
    return _platform.locked();
  }

  @override
  Future<RootClipboardSnapshot> read() async {
    if (_android) return _root.read();
    final map = await ClipboardSyncPlatform.methods
        .invokeMapMethod<Object?, Object?>('readClipboard');
    if (map == null) throw const FormatException('Missing clipboard snapshot');
    final metadata = RootClipboardMetadata.fromMap(map);
    return RootClipboardSnapshot(metadata, map['text'] as String?);
  }

  @override
  Future<void> write(String text) async {
    if (_android) {
      final snapshot = await _root.writeText(text);
      if (snapshot.text != text) {
        throw StateError('Clipboard write could not be verified');
      }
    } else {
      await ClipboardSyncPlatform.methods.invokeMethod<void>('writeClipboard', {
        'value': text,
      });
    }
  }

  @override
  Future<void> notifyReceived(String deviceName, String text) async {
    if (_android) return;
    try {
      await ClipboardSyncPlatform.methods.invokeMethod<void>(
        'notifyClipboardReceived',
        {'deviceName': deviceName, 'text': text, 'locale': _locale()},
      );
    } catch (_) {
      // A missing notification channel must not block clipboard delivery.
    }
  }

  @override
  Future<void> stop() async {
    if (_android) {
      try {
        await _root.stop();
      } catch (_) {
        /* service may already be shutting down */
      }
    }
  }
}
