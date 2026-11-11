import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_config.dart';
import '../models/clipboard_sync.dart';
import '../models/gotify_text_message.dart';
import '../services/clipboard_sync_engine.dart';
import '../services/clipboard_sync_platform.dart';
import 'config_provider.dart';

final clipboardSyncPlatformProvider = Provider(
  (ref) => const ClipboardSyncPlatform(),
);
final clipboardSyncProvider =
    StateNotifierProvider<ClipboardSyncController, ClipboardSyncUiState>((ref) {
      final controller = ClipboardSyncController(
        ref.read(clipboardSyncPlatformProvider),
      );
      ref.listen(configProvider, (previous, next) {
        final app = next.valueOrNull;
        if (app == null) return;
        unawaited(controller.configureConnection(app));
      }, fireImmediately: true);
      return controller;
    });
final clipboardSyncEnabledProvider = Provider(
  (ref) => ref.watch(clipboardSyncProvider).config?.enabled ?? false,
);

class ClipboardSyncUiState {
  const ClipboardSyncUiState({
    this.loaded = false,
    this.busy = false,
    this.config,
    this.status = const ClipboardSyncStatus(),
    this.error,
  });
  final bool loaded, busy;
  final ClipboardSyncConfig? config;
  final ClipboardSyncStatus status;
  final String? error;
  ClipboardSyncUiState copyWith({
    bool? loaded,
    bool? busy,
    ClipboardSyncConfig? config,
    ClipboardSyncStatus? status,
    String? error,
    bool clearError = false,
  }) => ClipboardSyncUiState(
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
    config: config ?? this.config,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
  );
}

typedef ClipboardSyncEngineBuilder =
    ClipboardSyncEngine Function(
      ClipboardSyncConfig config,
      void Function(ClipboardSyncStatus) onStatus,
    );

class ClipboardSyncController extends StateNotifier<ClipboardSyncUiState> {
  ClipboardSyncController(
    this.platform, {
    bool? android,
    Future<bool> Function()? canResumeAndroid,
    ClipboardSyncEngineBuilder? desktopEngineBuilder,
  }) : _android = android ?? Platform.isAndroid,
       _desktopEngineBuilder = desktopEngineBuilder,
       _canResumeAndroid =
           canResumeAndroid ??
           (() async =>
               !Platform.isAndroid ||
               (await Permission.notification.status).isGranted),
       super(const ClipboardSyncUiState());
  final bool _android;
  final Future<bool> Function() _canResumeAndroid;
  final ClipboardSyncEngineBuilder? _desktopEngineBuilder;
  final ClipboardSyncPlatform platform;
  StreamSubscription<ClipboardSyncStatus>? _status;
  ClipboardSyncEngine? _engine;
  bool _initializing = false;
  int _operation = 0;
  AppConfig? _app;

  Future<void> configureConnection(AppConfig app) async {
    _app = app;
    if (!state.loaded) {
      if (_initializing) return;
      _initializing = true;
      try {
        final saved = await platform.load();
        if (!mounted) return;
        final current = _app!;
        var status = const ClipboardSyncStatus();
        if (_android) {
          status = await platform.status();
          _status = platform.statuses.listen(
            _nativeStatus,
            onError: (Object _) {
              if (mounted) state = state.copyWith(error: 'platform_failed');
            },
          );
        }
        if (!mounted) return;
        final mismatch =
            saved != null &&
            (gotifyTextIdentity(saved.gotify) !=
                    gotifyTextIdentity(current.gotify) ||
                !current.gotify.enabled ||
                !_sameTargets(
                  saved.gotify.targetDeviceIds,
                  current.gotify.targetDeviceIds,
                ));
        final updated =
            (saved ??
                    ClipboardSyncConfig(
                      gotify: current.gotify,
                      name: current.localName,
                    ))
                .copyWith(gotify: current.gotify, name: current.localName);
        // The encrypted enabled flag is the user's previous choice, not a
        // snapshot of whether this process happens to have a running engine.
        final shouldResume =
            saved?.enabled == true && !mismatch && updated.valid;
        final config = updated.copyWith(enabled: shouldResume);
        if (_android && status.running && !shouldResume) {
          await platform.stopAndroid();
          status = const ClipboardSyncStatus();
        }
        if (saved != null) {
          // Migrate old snapshots without erasing an enabled choice at startup.
          await platform.save(config);
        }
        if (!mounted) return;
        final alreadyRunning = _android && status.running && shouldResume;
        state = ClipboardSyncUiState(
          loaded: true,
          busy: shouldResume && !alreadyRunning,
          config: config.copyWith(enabled: alreadyRunning),
          status: status,
        );
        if (shouldResume && !alreadyRunning) {
          if (_android && !await _canResumeAndroid()) {
            final disabled = config.copyWith(enabled: false);
            await platform.save(disabled);
            if (mounted) {
              state = state.copyWith(
                busy: false,
                config: disabled,
                error: 'notification_permission',
              );
            }
            return;
          }
          if (mounted) await _start(restoring: true);
        }
      } on MissingPluginException {
        if (mounted) {
          state = ClipboardSyncUiState(
            loaded: true,
            config: ClipboardSyncConfig(
              gotify: app.gotify,
              name: app.localName,
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          state = ClipboardSyncUiState(
            loaded: true,
            error: 'platform_failed',
            config: ClipboardSyncConfig(
              gotify: app.gotify,
              name: app.localName,
            ),
          );
        }
      } finally {
        _initializing = false;
      }
      return;
    }
    final old = state.config;
    if (old != null &&
        (gotifyTextIdentity(old.gotify) != gotifyTextIdentity(app.gotify) ||
            old.gotify.enabled != app.gotify.enabled ||
            !_sameTargets(
              old.gotify.targetDeviceIds,
              app.gotify.targetDeviceIds,
            ))) {
      await stop(force: true);
      if (!mounted) return;
      final cfg = old.copyWith(
        enabled: false,
        gotify: app.gotify,
        name: app.localName,
      );
      try {
        await platform.save(cfg);
      } catch (_) {}
      if (mounted) state = state.copyWith(config: cfg);
    }
  }

  bool _sameTargets(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _nativeStatus(ClipboardSyncStatus status) {
    if (!mounted) return;
    state = state.copyWith(
      status: status,
      config: status.phase == 'error'
          ? state.config?.copyWith(enabled: false)
          : null,
      busy: status.phase == 'error' ? false : null,
    );
    if (status.phase == 'error' || status.phase == 'stopped') {
      final token = _operation;
      unawaited(() async {
        try {
          final cfg = await platform.load();
          if (mounted &&
              token == _operation &&
              !state.busy &&
              state.status.phase == status.phase &&
              cfg != null &&
              !cfg.enabled) {
            state = state.copyWith(config: cfg);
          }
        } catch (_) {}
      }());
    }
  }

  Future<void> start() => _start();

  Future<void> _start({bool restoring = false}) async {
    if ((state.busy && !restoring) || state.config?.enabled == true) return;
    final cfg = state.config;
    if (cfg == null || !cfg.valid) {
      state = state.copyWith(error: 'settings_invalid');
      return;
    }
    final enabled = cfg.copyWith(enabled: true);
    final token = ++_operation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await platform.save(enabled);
      if (!mounted || token != _operation) return;
      state = state.copyWith(
        config: enabled,
        status: const ClipboardSyncStatus(phase: 'connecting'),
      );
      if (_android) {
        await platform.startAndroid();
      } else {
        late final ClipboardSyncEngine engine;
        void onEngineStatus(ClipboardSyncStatus status) {
          if (mounted && identical(_engine, engine)) {
            state = state.copyWith(status: status);
          }
        }

        engine =
            _desktopEngineBuilder?.call(enabled, onEngineStatus) ??
            ClipboardSyncEngine(
              config: enabled,
              clipboard: PlatformSyncClipboard(
                locale: () => _app?.locale ?? 'system',
              ),
              onStatus: onEngineStatus,
            );
        _engine = engine;
        await engine.start();
      }
      if (mounted && token == _operation) state = state.copyWith(busy: false);
    } catch (_) {
      if (!mounted || token != _operation) return;
      await _engine?.stop(report: false);
      _engine = null;
      try {
        if (_android) await platform.stopAndroid();
        await platform.save(cfg.copyWith(enabled: false));
      } catch (_) {}
      if (mounted) {
        state = state.copyWith(
          busy: false,
          config: cfg.copyWith(enabled: false),
          error: 'startup_failed',
          status: const ClipboardSyncStatus(
            phase: 'error',
            error: 'startup_failed',
          ),
        );
      }
    }
  }

  Future<void> stop({bool force = false}) async {
    if (state.busy && state.config?.enabled != true && !force) return;
    ++_operation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _engine?.stop();
      _engine = null;
      if (_android) await platform.stopAndroid();
      final cfg = state.config?.copyWith(enabled: false);
      if (cfg != null) await platform.save(cfg);
      if (mounted) {
        state = state.copyWith(
          config: cfg,
          busy: false,
          status: const ClipboardSyncStatus(),
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          busy: false,
          config: state.config?.copyWith(enabled: false),
          error: 'platform_failed',
        );
      }
    }
  }

  @override
  void dispose() {
    ++_operation;
    unawaited(_status?.cancel());
    final engine = _engine;
    _engine = null;
    if (engine != null) unawaited(engine.stop(report: false));
    // Android service intentionally survives UI/Activity disposal.
    super.dispose();
  }
}
