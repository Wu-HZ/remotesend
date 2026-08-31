import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/services/gotify_service.dart';

void main() {
  test(
    'GotifyService uses REST tokens and receives WebSocket messages',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final socketCompleter = Completer<WebSocket>();
      String? getToken;
      String? postToken;
      Map<String, dynamic>? postedBody;

      final serverSubscription = server.listen((request) async {
        if (request.uri.path == '/message' && request.method == 'GET') {
          getToken = request.headers.value('X-Gotify-Key');
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'paging': {'size': 1, 'limit': 200, 'since': 0, 'next': ''},
              'messages': [
                {
                  'id': 4,
                  'appid': 2,
                  'title': 'Previous',
                  'message': 'Previous event',
                  'date': '2026-08-26T00:00:00Z',
                  'extras': <String, dynamic>{},
                },
              ],
            }),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/message' && request.method == 'POST') {
          postToken = request.headers.value('X-Gotify-Key');
          postedBody = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 5,
              'appid': 2,
              'title': postedBody!['title'],
              'message': postedBody!['message'],
              'date': '2026-08-26T00:00:01Z',
              'extras': postedBody!['extras'],
            }),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/stream') {
          expect(request.uri.queryParameters['token'], 'client-token');
          final socket = await WebSocketTransformer.upgrade(request);
          socketCompleter.complete(socket);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final config = GotifyConfig(
        enabled: true,
        serverUrl: 'http://${server.address.host}:${server.port}',
        appToken: 'app-token',
        clientToken: 'client-token',
        deviceId: 'device-a',
      );
      final service = GotifyService(config);

      try {
        final page = await service.fetchMessages();
        expect(getToken, 'client-token');
        expect(page.messages.single.id, 4);

        final event = RemoteSendEvent(
          type: RemoteSendEvent.textChanged,
          eventId: 'event-1',
          senderDeviceId: 'device-a',
          senderName: 'Phone A',
          payload: const {'date': '2026-08-26'},
        );
        final sent = await service.send(
          event: event,
          title: 'RemoteSend',
          message: 'New text',
        );
        expect(postToken, 'app-token');
        expect(sent.id, 5);
        expect(
          (postedBody!['extras'] as Map).containsKey(RemoteSendEvent.extrasKey),
          isTrue,
        );

        await service.connect();
        final receivedFuture = service.messages.first;
        final socket = await socketCompleter.future;
        socket.add(
          jsonEncode({
            'id': 6,
            'appid': 2,
            'title': 'RemoteSend',
            'message': 'Incoming',
            'date': '2026-08-26T00:00:02Z',
            'extras': event.toExtras(),
          }),
        );
        final received = await receivedFuture.timeout(
          const Duration(seconds: 2),
        );
        expect(received.id, 6);
        expect(RemoteSendEvent.fromGotifyMessage(received)?.eventId, 'event-1');
      } finally {
        await service.close();
        await serverSubscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
