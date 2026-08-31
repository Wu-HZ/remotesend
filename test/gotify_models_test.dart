import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/services/gotify_runtime_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GotifyConfig', () {
    test('round-trips per-device settings', () {
      final config = GotifyConfig(
        enabled: true,
        serverUrl: 'https://gotify.example.com',
        appToken: 'app-token',
        clientToken: 'client-token',
        deviceId: 'device-a',
        autoDownloadEnabled: true,
        wifiOnly: true,
        maxAutoDownloadBytes: 1024,
        targetDeviceIds: const ['device-b', 'device-c'],
        historyLookbackMinutes: 5,
      );

      expect(GotifyConfig.fromJson(config.toJson()), config);
      expect(config.isConfigured, isTrue);
    });

    test('clamps lookback and checks event age', () {
      final now = DateTime.utc(2026, 8, 31, 12);
      final config = GotifyConfig(historyLookbackMinutes: 3);

      expect(GotifyConfig(historyLookbackMinutes: 0).historyLookbackMinutes, 1);
      expect(GotifyConfig(historyLookbackMinutes: 9).historyLookbackMinutes, 5);
      expect(
        config.isWithinHistoryLookback(
          now.subtract(const Duration(minutes: 2)),
          now: now,
        ),
        isTrue,
      );
      expect(
        config.isWithinHistoryLookback(
          now.subtract(const Duration(minutes: 4)),
          now: now,
        ),
        isFalse,
      );
    });

    test('creates a stable non-empty device ID when absent', () {
      final config = GotifyConfig.fromJson(const {});
      final restored = GotifyConfig.fromJson(config.toJson());

      expect(config.deviceId, isNotEmpty);
      expect(restored.deviceId, config.deviceId);
    });
  });

  group('RemoteSendEvent', () {
    test('round-trips through Gotify extras and targets devices', () {
      final event = RemoteSendEvent(
        type: RemoteSendEvent.fileReady,
        eventId: 'event-1',
        senderDeviceId: 'device-a',
        senderName: 'Phone A',
        targetDeviceIds: const ['device-b'],
        payload: const {'fileName': 'report.pdf', 'fileSize': 42},
        createdAt: DateTime.utc(2026, 8, 26),
      );
      final message = GotifyMessage.fromJson({
        'id': 12,
        'appid': 3,
        'title': 'RemoteSend',
        'message': 'File ready',
        'date': '2026-08-26T00:00:00Z',
        'extras': event.toExtras(),
      });

      final restored = RemoteSendEvent.fromGotifyMessage(message);
      expect(restored, isNotNull);
      expect(restored!.eventId, 'event-1');
      expect(restored.payload['fileName'], 'report.pdf');
      expect(restored.isForDevice('device-b'), isTrue);
      expect(restored.isForDevice('device-c'), isFalse);
      expect(restored.isForDevice('device-a'), isFalse);
    });
  });

  test('WebDAV server key ignores URL case and trailing slash', () {
    final first = ServerConfig.create(
      name: 'A',
      serverUrl: 'HTTPS://Example.COM/dav/',
      username: 'user',
      password: 'secret',
    );
    final second = ServerConfig.create(
      name: 'B',
      serverUrl: 'https://example.com/dav',
      username: 'user',
      password: 'different-secret',
    );

    expect(webDavServerKey(first), webDavServerKey(second));
  });

  test('runtime store cancels inbound work but persists outbox', () async {
    SharedPreferences.setMockInitialValues({});
    final store = GotifyRuntimeStore('test');
    final event = RemoteSendEvent(
      type: RemoteSendEvent.fileReady,
      eventId: 'pending-event',
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
    );

    await store.save(
      GotifyRuntimeData(
        lastMessageId: 9,
        pendingInboundEvents: [event],
        outbox: [
          PendingGotifyEvent(
            event: event,
            title: 'RemoteSend',
            message: 'File ready',
            priority: 1,
          ),
        ],
      ),
    );
    final restored = await store.load();

    expect(restored.lastMessageId, 9);
    expect(restored.pendingInboundEvents, isEmpty);
    expect(restored.outbox.single.event.eventId, 'pending-event');
  });

  test('AppConfig migrates retired polling keys and stores Gotify', () {
    final config = AppConfig.fromJson({
      'version': 5,
      'servers': <Object>[],
      'refreshIntervalSeconds': 3,
      'autoSyncEnabled': true,
      'gotify': {
        'enabled': true,
        'serverUrl': 'https://gotify.example.com',
        'appToken': 'app',
        'clientToken': 'client',
        'deviceId': 'device-a',
      },
    });
    final encoded = config.toJson();

    expect(config.version, AppConfig.currentVersion);
    expect(config.gotify.deviceId, 'device-a');
    expect(encoded, isNot(contains('refreshIntervalSeconds')));
    expect(encoded, isNot(contains('autoSyncEnabled')));
    expect(encoded['gotify'], isA<Map<String, dynamic>>());
    final encodedGotify = encoded['gotify'] as Map<String, dynamic>;
    expect(encodedGotify['appToken'], 'app');
    expect(encodedGotify['clientToken'], 'client');
    expect(encodedGotify['historyLookbackMinutes'], 3);
  });
}
