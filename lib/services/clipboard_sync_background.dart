import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/clipboard_sync.dart';
import 'clipboard_sync_engine.dart';
import 'clipboard_sync_platform.dart';

ClipboardSyncEngine? _backgroundEngine;

/// Invoked only by Android's explicit foreground service, not a UI route.
Future<void> startClipboardSyncBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  const platform = ClipboardSyncPlatform();
  try {
    final config = await platform.load();
    if (config == null || !config.enabled || !config.valid) {
      throw StateError('Invalid sync settings');
    }
    var failed = false;
    _backgroundEngine = ClipboardSyncEngine(
      config: config,
      clipboard: PlatformSyncClipboard(android: true),
      onStatus: (status) {
        unawaited(() async {
          try {
            await platform.report(status);
            if (status.phase == 'error' && !failed) {
              failed = true;
              await platform.abortAndroid();
            }
          } catch (_) {
            /* owner already destroyed the engine */
          }
        }());
      },
    );
    await _backgroundEngine!.start();
  } catch (_) {
    try {
      await platform.report(
        const ClipboardSyncStatus(phase: 'error', error: 'startup_failed'),
      );
      await platform.abortAndroid();
    } catch (_) {
      /* no contents/exception messages in logs */
    }
  }
}
