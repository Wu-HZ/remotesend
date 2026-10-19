import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/models/server_endpoint.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/gotify_provider.dart';
import 'package:remote_send/providers/gotify_text_session_provider.dart';
import 'package:remote_send/providers/message_history_provider.dart';
import 'package:remote_send/providers/text_send_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/services/config_service.dart';

class _Store extends ConfigService {
  @override
  Future<bool> saveConfig(AppConfig config) async => true;
}

class _Config extends ConfigNotifier {
  _Config(String url, String device) : super(_Store()) {
    state = AsyncData(
      AppConfig(
        activeTextServerId: gotifyTextServerId,
        gotify: GotifyConfig(
          enabled: true,
          registerAsTextServer: true,
          serverUrl: url,
          appToken: 'application-token',
          clientToken: 'client-$device',
          deviceId: device,
          targetDeviceIds: device == 'a' ? ['b'] : [],
        ),
      ),
    );
  }
}

void main() {
  test(
    'two real REST/WebSocket clients exchange direct text with zero WebDAV calls and no body persistence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final directBodies = <Map<String, dynamic>>[];
      final paths = <String>[];
      var id = 0;
      server.listen((request) async {
        paths.add(request.uri.path);
        if (request.uri.path == '/stream') {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          return;
        }
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.path == '/message') {
          expect(request.headers.value('X-Gotify-Key'), startsWith('client-'));
          request.response.write(jsonEncode({'messages': [], 'paging': {}}));
        } else if (request.method == 'POST' && request.uri.path == '/message') {
          expect(request.headers.value('X-Gotify-Key'), 'application-token');
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          final message = {
            'id': ++id,
            'appid': 7,
            'title': body['title'],
            'message': body['message'],
            'date': DateTime.now().toUtc().toIso8601String(),
            'extras': body['extras'],
          };
          final event = RemoteSendEvent.fromJson(
            Map<String, dynamic>.from(
              (body['extras'] as Map)[RemoteSendEvent.extrasKey],
            ),
          );
          if (event.type == RemoteSendEvent.textDirect) directBodies.add(body);
          request.response.write(jsonEncode(message));
          for (final socket in sockets) {
            if (socket.readyState == WebSocket.open) {
              socket.add(jsonEncode(message));
            }
          }
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      final url = 'http://${server.address.address}:${server.port}';
      ProviderContainer client(String device) => ProviderContainer(
        overrides: [
          configProvider.overrideWith((ref) => _Config(url, device)),
          webDavTextServiceProvider.overrideWith(
            (ref) => throw StateError('No WebDAV transport'),
          ),
          messageHistoryProvider.overrideWith(
            (ref) => throw StateError('No WebDAV history'),
          ),
        ],
      );
      final a = client('a');
      final b = client('b');
      final subscriptions = <StreamSubscription<RemoteSendEvent>>[];
      for (final client in [a, b]) {
        final session = client.read(gotifyTextSessionProvider.notifier);
        subscriptions.add(
          client.read(gotifyProvider.notifier).events.listen((event) {
            if (event.type == RemoteSendEvent.textDirect) {
              session.receive(event);
            }
          }),
        );
      }
      Future<void> waitFor(bool Function() complete) async {
        for (var i = 0; !complete() && i < 500; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(complete(), isTrue);
      }

      try {
        await waitFor(
          () =>
              a.read(gotifyProvider).isConnected &&
              b.read(gotifyProvider).isConnected,
        );
        expect(
          await a
              .read(textSendControllerProvider)
              .send('SECRET_BIDIRECTIONAL_A\n你好🙂'),
          isTrue,
        );
        await waitFor(
          () => b.read(gotifyTextSessionProvider).messages.length == 1,
        );
        expect(
          b.read(gotifyTextSessionProvider).messages.single.content,
          'SECRET_BIDIRECTIONAL_A\n你好🙂',
        );
        expect(
          await b
              .read(textSendControllerProvider)
              .send('SECRET_BIDIRECTIONAL_B'),
          isTrue,
        );
        await waitFor(
          () => a.read(gotifyTextSessionProvider).messages.length == 2,
        );
        expect(
          a.read(gotifyTextSessionProvider).messages.last.isLocal,
          isFalse,
        );
        expect(
          a.read(gotifyTextSessionProvider).messages.last.content,
          'SECRET_BIDIRECTIONAL_B',
        );
        expect(directBodies, hasLength(2));
        expect(
          directBodies.every(
            (body) => body['message'] == 'RemoteSend real-time text',
          ),
          isTrue,
        );
        expect(
          paths.every((path) => path == '/message' || path == '/stream'),
          isTrue,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().map((key) => prefs.get(key).toString()).join(),
          isNot(contains('SECRET_BIDIRECTIONAL')),
        );
      } finally {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        a.dispose();
        b.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
  );
}
