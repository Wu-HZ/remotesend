import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/clipboard_sync.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/providers/clipboard_sync_provider.dart';
import 'package:remote_send/providers/gotify_provider.dart';
import 'package:remote_send/screens/clipboard_sync_screen.dart';
import 'package:remote_send/services/clipboard_sync_platform.dart';

class _Platform extends ClipboardSyncPlatform {
  ClipboardSyncConfig? saved;
  ClipboardSyncStatus current = const ClipboardSyncStatus();
  final stream = StreamController<ClipboardSyncStatus>.broadcast(sync: true);
  int starts = 0, stops = 0;
  @override
  Future<ClipboardSyncConfig?> load() async => saved;
  @override
  Future<void> save(ClipboardSyncConfig cfg) async {
    saved = ClipboardSyncConfig.fromJson(cfg.toJson());
  }

  @override
  Stream<ClipboardSyncStatus> get statuses => stream.stream;
  @override
  Future<ClipboardSyncStatus> status() async => current;
  @override
  Future<void> startAndroid() async {
    starts++;
    current = const ClipboardSyncStatus(phase: 'waiting');
    stream.add(current);
  }

  @override
  Future<void> stopAndroid() async {
    stops++;
    saved = saved?.copyWith(enabled: false);
    current = const ClipboardSyncStatus();
    stream.add(current);
  }
}

class _Gotify extends StateNotifier<GotifyState> implements GotifyNotifier {
  _Gotify() : super(const GotifyState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppConfig _app() => AppConfig(
  localName: 'PC',
  gotify: GotifyConfig(
    enabled: true,
    serverUrl: 'https://gotify.invalid',
    appToken: 'app',
    clientToken: 'client',
    deviceId: 'local',
    targetDeviceIds: ['phone'],
  ),
);

void main() {
  test(
    'old paired-key settings migrate without a key to the existing Gotify targets',
    () {
      final app = _app();
      final old = ClipboardSyncConfig.fromJson({
        'version': 1,
        'gotify': app.gotify.toJson(),
        'name': app.localName,
        'enabled': false,
        'send': true,
        'receive': true,
        'secret': 'rsclip1:old-unused-key',
        'peers': ['obsolete-peer-list'],
      });
      expect(old.valid, isTrue);
      expect(old.gotify.targetDeviceIds, ['phone']);
      expect(old.toJson()['version'], 2);
      expect(old.toJson().containsKey('secret'), isFalse);
      expect(old.toJson().containsKey('peers'), isFalse);
    },
  );

  test(
    'service is not auto-started; leaving UI preserves it; explicit stop disables',
    () async {
      final platform = _Platform(), app = _app();
      var controller = ClipboardSyncController(platform, android: true);
      try {
        await controller.configureConnection(app);
        expect(platform.starts, 0);
        expect(controller.state.config!.gotify.targetDeviceIds, ['phone']);
        await controller.start();
        expect(platform.starts, 1);
        expect(controller.state.config!.enabled, isTrue);
        controller.dispose();
        expect(platform.stops, 0);
        controller = ClipboardSyncController(platform, android: true);
        await controller.configureConnection(app);
        expect(controller.state.config!.enabled, isTrue);
        expect(platform.starts, 1);
        await controller.stop();
        expect(platform.saved!.enabled, isFalse);
        expect(platform.stops, 1);
      } finally {
        controller.dispose();
        await platform.stream.close();
      }
    },
  );

  test(
    'stale saved enabled flag does not automatically request Root on a fresh launch',
    () async {
      final platform = _Platform(), app = _app();
      platform.saved = ClipboardSyncConfig(
        gotify: app.gotify,
        name: app.localName,
        enabled: true,
      );
      final controller = ClipboardSyncController(platform, android: true);
      try {
        await controller.configureConnection(app);
        expect(controller.state.config!.enabled, isFalse);
        expect(platform.saved!.enabled, isFalse);
        expect(platform.starts, 0);
      } finally {
        controller.dispose();
        await platform.stream.close();
      }
    },
  );

  test(
    'changing Gotify credentials or targets stops the old service',
    () async {
      final platform = _Platform(), app = _app();
      final controller = ClipboardSyncController(platform, android: true);
      try {
        await controller.configureConnection(app);
        await controller.start();
        await controller.configureConnection(
          app.copyWith(
            gotify: app.gotify.copyWith(serverUrl: 'https://new.invalid'),
          ),
        );
        expect(platform.stops, 1);
        expect(controller.state.config!.enabled, isFalse);
        expect(platform.saved!.gotify.serverUrl, 'https://new.invalid');
        expect(platform.saved!.gotify.targetDeviceIds, ['phone']);
        await controller.configureConnection(
          app.copyWith(
            gotify: app.gotify.copyWith(targetDeviceIds: ['other-phone']),
          ),
        );
        expect(platform.stops, 2);
        expect(platform.saved!.gotify.targetDeviceIds, ['other-phone']);
      } finally {
        controller.dispose();
        await platform.stream.close();
      }
    },
  );

  testWidgets(
    'simple switch uses Gotify targets; no pairing key or peer setup is shown',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 850));
      final platform = _Platform(), app = _app();
      final controller = ClipboardSyncController(platform, android: true);
      await controller.configureConnection(app);
      final container = ProviderContainer(
        overrides: [
          clipboardSyncProvider.overrideWith((ref) => controller),
          gotifyProvider.overrideWith((ref) => _Gotify()),
        ],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              locale: Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ClipboardSyncScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('clipboard-sync-switch')),
          findsOneWidget,
        );
        expect(find.text('phone'), findsNWidgets(2));
        expect(find.byKey(const ValueKey('clipboard-sync-key')), findsNothing);
        expect(find.byKey(const ValueKey('clipboard-sync-peer')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('clipboard-sync-switch')));
        await tester.pumpAndSettle();
        expect(platform.starts, 1);
        expect(controller.state.config!.enabled, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await platform.stream.close();
        await tester.binding.setSurfaceSize(null);
      }
    },
  );
}
