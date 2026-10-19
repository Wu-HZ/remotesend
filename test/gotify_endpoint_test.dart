import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/models/server_endpoint.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/text_endpoint_provider.dart';
import 'package:remote_send/services/config_service.dart';

class _Store extends ConfigService {
  @override
  Future<bool> saveConfig(AppConfig config) async => true;
}

class _Config extends ConfigNotifier {
  _Config(AppConfig config) : super(_Store()) {
    state = AsyncData(config);
  }
}

void main() {
  final server = ServerConfig.create(
    name: 'WebDAV',
    serverUrl: 'https://dav.invalid',
    username: 'u',
    password: 'p',
  );
  GotifyConfig gotify({bool registered = true}) => GotifyConfig(
    enabled: true,
    registerAsTextServer: registered,
    serverUrl: 'https://gotify.invalid',
    appToken: 'app',
    clientToken: 'client',
  );

  test(
    'device capabilities round-trip while older devices remain compatible',
    () {
      final device = RemoteDevice(
        id: 'peer',
        name: 'Phone',
        platform: 'android',
        lastSeen: DateTime.utc(2026),
        capabilities: ['text_direct_v1'],
      );
      expect(RemoteDevice.fromJson(device.toJson()).capabilities, [
        'text_direct_v1',
      ]);
      final old = Map<String, dynamic>.from(device.toJson())
        ..remove('capabilities');
      expect(RemoteDevice.fromJson(old).capabilities, isEmpty);
    },
  );

  test('registration is opt-in and survives JSON/copy', () {
    expect(GotifyConfig.fromJson({}).registerAsTextServer, isFalse);
    final config = AppConfig(gotify: gotify());
    final loaded = AppConfig.fromJsonString(config.toJsonString());
    expect(loaded.gotify.registerAsTextServer, isTrue);
    expect(loaded.gotify.copyWith(enabled: false).registerAsTextServer, isTrue);
  });
  test(
    'Gotify emoji survives persistence, copy, equality and older configs',
    () {
      final original = gotify().copyWith(emoji: '🚀');
      final loaded = AppConfig.fromJsonString(
        AppConfig(gotify: original).toJsonString(),
      ).gotify;
      expect(loaded, original);
      expect(loaded.hashCode, original.hashCode);
      expect(loaded.copyWith(enabled: false).emoji, '🚀');
      expect(GotifyTextEndpoint(loaded).emoji, '🚀');
      expect(loaded.copyWith(emoji: '💡'), isNot(loaded));
      expect(GotifyTextEndpoint(loaded.copyWith(emoji: '')).emoji, isEmpty);
      expect(
        GotifyConfig.fromJson(original.toJson()..remove('emoji')).emoji,
        isEmpty,
      );
      expect(GotifyConfig.fromJson(null).emoji, isEmpty);
    },
  );
  test(
    'Gotify selection never falls back to WebDAV or becomes a file server',
    () {
      final config = AppConfig(
        servers: [server],
        activeTextServerId: gotifyTextServerId,
        activeFilesServerId: gotifyTextServerId,
        gotify: gotify(),
      );
      expect(config.activeTextServer, isNull);
      expect(config.activeFilesServer, isNull);
      expect(config.isTextConfigured, isTrue);
      expect(config.normalizeServerSelections().activeFilesServerId, isNull);
    },
  );
  test(
    'only Gotify can be configured without WebDAV and unregister clears selection',
    () {
      final config = AppConfig(
        activeTextServerId: gotifyTextServerId,
        gotify: gotify(),
      );
      expect(config.isConfigured, isTrue);
      expect(config.isFilesConfigured, isFalse);
      expect(
        config
            .copyWith(gotify: gotify(registered: false))
            .normalizeServerSelections()
            .activeTextServerId,
        isNull,
      );
    },
  );
  test(
    'unregister atomically falls back to enabled WebDAV without changing file selection',
    () {
      final config = AppConfig(
        servers: [server],
        activeTextServerId: gotifyTextServerId,
        activeFilesServerId: server.id,
        gotify: gotify(registered: false),
      );
      final normalized = config.normalizeServerSelections();
      expect(normalized.activeTextServerId, server.id);
      expect(normalized.activeFilesServerId, server.id);
    },
  );
  test(
    'endpoint list includes Gotify exactly once and file list excludes it',
    () async {
      final notifier = _Config(AppConfig(servers: [server], gotify: gotify()));
      final container = ProviderContainer(
        overrides: [configProvider.overrideWith((ref) => notifier)],
      );
      addTearDown(container.dispose);
      expect(container.read(textServerEndpointsProvider).map((e) => e.id), [
        server.id,
        gotifyTextServerId,
      ]);
      expect(container.read(enabledServersProvider).map((e) => e.id), [
        server.id,
      ]);
      expect(await notifier.switchTextServer(gotifyTextServerId), isTrue);
      expect(
        container.read(activeTextEndpointProvider),
        isA<GotifyTextEndpoint>(),
      );
      expect(await notifier.switchFilesServer(gotifyTextServerId), isFalse);
      expect(
        await notifier.setServerForFeature(
          gotifyTextServerId,
          forText: true,
          forFiles: true,
        ),
        isFalse,
      );
    },
  );
}
