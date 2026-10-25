import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/clipboard_sync.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/models/root_clipboard.dart';
import 'package:remote_send/services/clipboard_sync_engine.dart';
import 'package:remote_send/services/gotify_service.dart';

class _Clipboard implements SyncClipboard {
  String text = 'existing clipboard';
  bool isLocked = false, internal = false, sensitive = false;
  final writes = <String>[];
  final notifications = <(String, String)>[];
  @override
  bool get eventDriven => false;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> notifyReceived(String deviceName, String text) async =>
      notifications.add((deviceName, text));
  @override
  Future<void> stop() async {}
  @override
  Future<bool> locked() async => isLocked;
  @override
  Future<RootClipboardSnapshot> read() async => RootClipboardSnapshot(
    RootClipboardMetadata(
      kind: sensitive ? RootClipboardKind.sensitive : RootClipboardKind.text,
      bytes: sensitive ? null : utf8.encode(text).length,
      internal: internal,
    ),
    sensitive ? null : text,
  );
  @override
  Future<void> write(String text) async {
    this.text = text;
    internal = true;
    writes.add(text);
  }

  void copy(String value) {
    text = value;
    internal = false;
  }
}

class _Broker {
  int id = 0;
  final clients = <_Transport>[];
  final messages = <GotifyMessage>[];
  final deletedIds = <int>[];
  Completer<void>? hold;
  String? holdDevice;
  int held = 0;
  bool failData = false;
  _Transport create(GotifyConfig config) {
    final c = _Transport(config, this);
    clients.add(c);
    return c;
  }

  void deliver(GotifyMessage message) {
    for (final c in clients.where((c) => c.connected).toList()) {
      c.stream.add(message);
    }
  }
}

class _Transport extends GotifyService {
  _Transport(super.config, this.broker);
  final _Broker broker;
  final stream = StreamController<GotifyMessage>.broadcast();
  bool connected = false;
  @override
  Stream<GotifyMessage> get messages => stream.stream;
  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  Future<GotifyMessage> send({
    required RemoteSendEvent event,
    required String title,
    required String message,
    int priority = 0,
  }) async {
    if (message == 'Clipboard sync text') {
      if (broker.failData) throw const GotifyException('send_failed');
      if (broker.hold != null && broker.holdDevice == event.senderDeviceId) {
        broker.held++;
        await broker.hold!.future;
      }
    }
    final result = GotifyMessage(
      id: ++broker.id,
      applicationId: 7,
      title: title,
      message: message,
      date: event.createdAt,
      extras: event.toExtras(),
    );
    broker.messages.add(result);
    broker.deliver(result);
    return result;
  }

  @override
  Future<void> deleteMessage(int id) async => broker.deletedIds.add(id);
  @override
  Future<void> close() async {
    connected = false;
    await stream.close();
  }
}

ClipboardSyncConfig _config(String id, [String? target]) => ClipboardSyncConfig(
  gotify: GotifyConfig(
    enabled: true,
    serverUrl: 'https://gotify.invalid',
    appToken: 'app',
    clientToken: 'client',
    deviceId: id,
    targetDeviceIds: target == null ? const [] : [target],
  ),
  name: id,
  enabled: true,
);

void main() {
  test(
    'clipboard sync is an ordinary Gotify text event and needs no extra key',
    () {
      final config = _config('a', 'b');
      expect(config.valid, isTrue);
      expect(config.gotify.targetDeviceIds, ['b']);
      expect(config.toJson().containsKey('secret'), isFalse);
      expect(config.toJson().containsKey('peers'), isFalse);
      expect(_config('broadcast').valid, isTrue);
      expect(_config('broadcast').gotify.targetDeviceIds, isEmpty);
      final event = RemoteSendEvent(
        type: ClipboardSyncEngine.eventType,
        senderDeviceId: 'a',
        senderName: 'A',
        targetDeviceIds: ['b'],
        payload: {
          'version': 1,
          'kind': 'clip',
          'session': 'session-a',
          'text': '  hello\n',
        },
      );
      final wire = jsonEncode(event.toExtras());
      expect(wire, contains('hello'));
      expect(
        RemoteSendEvent.fromGotifyMessage(
          GotifyMessage(
            id: 1,
            applicationId: 7,
            title: 'RemoteSend clipboard',
            message: 'Clipboard sync text',
            date: event.createdAt,
            extras: event.toExtras(),
          ),
        )!.payload['text'],
        '  hello\n',
      );
      expect(ClipboardSyncEngine.validText('  \n  '), isTrue);
      expect(ClipboardSyncEngine.validText('x\u0000y'), isFalse);
      expect(ClipboardSyncEngine.validText('你' * 11000), isFalse);
    },
  );
  test(
    'bidirectional sync preserves text, skips initial data, does not echo, and rejects old-session replay',
    () async {
      final broker = _Broker(), a = _Clipboard(), b = _Clipboard();
      final statsA = <ClipboardSyncStatus>[], statsB = <ClipboardSyncStatus>[];
      var stage = 'startup';
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Timed out at $stage: statusA=${statsA.last.phase}/${statsA.last.peers}, statusB=${statsB.last.phase}/${statsB.last.peers}, events=${broker.messages.map((m) {
                final e = RemoteSendEvent.fromGotifyMessage(m)!;
                return '${m.id}:${e.senderDeviceId}->${e.targetDeviceIds}:${e.payload['kind']}';
              }).toList()}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      ClipboardSyncEngine engine(
        String id,
        String peer,
        _Clipboard cb,
        List<ClipboardSyncStatus> stats,
      ) => ClipboardSyncEngine(
        config: _config(id, peer),
        clipboard: cb,
        onStatus: stats.add,
        transport: broker.create,
        pollInterval: const Duration(milliseconds: 10),
        helloInterval: const Duration(seconds: 1),
      );
      final ea = engine('a', 'b', a, statsA);
      var eb = engine('b', 'a', b, statsB);
      try {
        await ea.start();
        await eb.start();
        stage = 'initial handshake';
        await until(() => statsA.last.peers == 1 && statsB.last.peers == 1);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(a.writes, isEmpty);
        expect(b.writes, isEmpty);
        expect(statsA.last.peers, 1);
        expect(statsB.last.peers, 1);
        a.copy('  你好 ✓\n  ');
        stage = 'first-to-second copy';
        await until(() => b.text == '  你好 ✓\n  ');
        expect(b.text, '  你好 ✓\n  ');
        expect(b.notifications, [('a', '  你好 ✓\n  ')]);
        final first = broker.messages.lastWhere(
          (m) => m.message == 'Clipboard sync text',
        );
        final sentBefore = broker.messages
            .where((m) => m.message == 'Clipboard sync text')
            .length;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          broker.messages
              .where((m) => m.message == 'Clipboard sync text')
              .length,
          sentBefore,
        );
        b.copy('reply');
        stage = 'second-to-first copy';
        await until(() => a.text == 'reply');
        expect(a.text, 'reply');
        expect(a.notifications, [('b', 'reply')]);
        final clipIds = broker.messages
            .where((m) => m.message == 'Clipboard sync text')
            .map((m) => m.id);
        expect(broker.deletedIds, containsAll(clipIds));
        await eb.stop();
        eb = engine('b', 'a', b, statsB);
        await eb.start();
        stage = 'restart handshake';
        await until(() => statsA.last.peers == 1 && statsB.last.peers == 1);
        final count = b.writes.length;
        broker.deliver(first);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(b.writes.length, count);
        expect(b.text, 'reply');
      } finally {
        await ea.stop();
        await eb.stop();
      }
    },
  );

  test(
    'real HTTP/WebSocket transports exchange Gotify text clips without any history GET',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final posts = <String>[];
      var id = 0, historyGets = 0;
      final serving = server.listen((request) async {
        if (request.uri.path == '/nested/stream') {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.listen((_) {});
        } else if (request.method == 'POST' &&
            request.uri.path == '/nested/message') {
          final raw = await utf8.decoder.bind(request).join();
          posts.add(raw);
          final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          json.addAll({
            'id': ++id,
            'appid': 7,
            'date': DateTime.now().toUtc().toIso8601String(),
          });
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(json));
          await request.response.close();
          for (final socket in sockets.where(
            (s) => s.readyState == WebSocket.open,
          )) {
            socket.add(jsonEncode(json));
          }
        } else if (request.method == 'DELETE' &&
            request.uri.path.startsWith('/nested/message/')) {
          request.response.statusCode = 204;
          await request.response.close();
        } else {
          historyGets++;
          request.response.statusCode = 405;
          await request.response.close();
        }
      });
      final a = _Clipboard(), b = _Clipboard();
      final statsA = <ClipboardSyncStatus>[], statsB = <ClipboardSyncStatus>[];
      ClipboardSyncEngine make(
        String device,
        String peer,
        _Clipboard cb,
        List<ClipboardSyncStatus> stats,
      ) {
        final cfg = _config(device, peer);
        return ClipboardSyncEngine(
          config: cfg.copyWith(
            gotify: cfg.gotify.copyWith(
              serverUrl: 'http://127.0.0.1:${server.port}/nested',
            ),
          ),
          clipboard: cb,
          onStatus: stats.add,
          pollInterval: const Duration(milliseconds: 20),
          helloInterval: const Duration(seconds: 1),
        );
      }

      final ea = make('a', 'b', a, statsA), eb = make('b', 'a', b, statsB);
      Future<void> until(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Real transport timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      try {
        await ea.start();
        await eb.start();
        await until(() => statsA.last.peers == 1 && statsB.last.peers == 1);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        a.copy('SECRET_PC_VALUE\n  ');
        await until(() => b.text == a.text);
        b.copy('SECRET_PHONE_VALUE');
        await until(() => a.text == b.text);
        expect(posts.join(), contains('SECRET_PC_VALUE'));
        expect(posts.join(), contains('SECRET_PHONE_VALUE'));
        expect(posts.join(), contains('SECRET_PHONE_VALUE'));
        expect(historyGets, 0);
      } finally {
        await ea.stop();
        await eb.stop();
        for (final socket in sockets) {
          await socket.close();
        }
        await serving.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'rapid copies keep only the latest pending value and a local send wins over older inbound data',
    () async {
      final broker = _Broker(), a = _Clipboard(), b = _Clipboard();
      final sa = <ClipboardSyncStatus>[], sb = <ClipboardSyncStatus>[];
      ClipboardSyncEngine make(
        String id,
        String peer,
        _Clipboard clip,
        List<ClipboardSyncStatus> states,
      ) => ClipboardSyncEngine(
        config: _config(id, peer),
        clipboard: clip,
        transport: broker.create,
        onStatus: states.add,
        pollInterval: const Duration(milliseconds: 10),
        helloInterval: const Duration(seconds: 1),
      );
      final ea = make('a', 'b', a, sa), eb = make('b', 'a', b, sb);
      Future<void> until(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Copy coalescing timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      try {
        await ea.start();
        await eb.start();
        await until(() => sa.last.peers == 1 && sb.last.peers == 1);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        broker.hold = Completer();
        broker.holdDevice = 'a';
        a.copy('first');
        await until(() => broker.held == 1);
        b.copy('older remote');
        await until(() => sb.last.sent == 1);
        expect(a.text, 'first');
        a.copy('middle');
        await Future<void>.delayed(const Duration(milliseconds: 25));
        a.copy('latest');
        await Future<void>.delayed(const Duration(milliseconds: 25));
        broker.hold!.complete();
        await until(() => b.text == 'latest');
        expect(a.text, 'latest');
        final bodies = <String>[];
        for (final m in broker.messages.where(
          (m) => m.message == 'Clipboard sync text',
        )) {
          bodies.add(
            RemoteSendEvent.fromGotifyMessage(m)!.payload['text'] as String,
          );
        }
        expect(bodies, isNot(contains('middle')));
        expect(sa.last.sent, 2);
      } finally {
        if (broker.hold?.isCompleted == false) broker.hold!.complete();
        await ea.stop();
        await eb.stop();
      }
    },
  );

  test(
    'sensitive clips are never sent or overwritten; lock/unlock does not replay; expired frames are discarded',
    () async {
      final broker = _Broker(), a = _Clipboard(), b = _Clipboard();
      final sa = <ClipboardSyncStatus>[], sb = <ClipboardSyncStatus>[];
      var jump = Duration.zero;
      ClipboardSyncEngine make(
        String id,
        String peer,
        _Clipboard cb,
        List<ClipboardSyncStatus> states,
      ) => ClipboardSyncEngine(
        config: _config(id, peer),
        clipboard: cb,
        onStatus: states.add,
        transport: broker.create,
        now: () => DateTime.now().add(jump),
        pollInterval: const Duration(milliseconds: 10),
        helloInterval: const Duration(seconds: 1),
      );
      final ea = make('a', 'b', a, sa), eb = make('b', 'a', b, sb);
      Future<void> until(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Boundary test timed out: A=${sa.last.phase}/${sa.last.peers}/${sa.last.sent}, B=${sb.last.phase}/${sb.last.peers}/${sb.last.sent}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      try {
        await ea.start();
        await eb.start();
        await until(() => sa.last.peers == 1 && sb.last.peers == 1);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        a.sensitive = true;
        a.copy('password');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(sa.last.sent, 0);
        b.copy('must not overwrite password');
        await until(() => sb.last.sent == 1);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(a.text, 'password');
        a.sensitive = false;
        a.copy('safe baseline');
        await until(() => b.text == 'safe baseline');
        b.isLocked = true;
        await until(() => sb.last.phase == 'paused');
        a.copy('while locked');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(b.text, 'safe baseline');
        b.isLocked = false;
        await until(
          () =>
              sa.last.peers == 1 &&
              sb.last.peers == 1 &&
              sb.last.phase == 'running',
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(b.text, 'safe baseline');
        broker.hold = Completer();
        broker.holdDevice = 'a';
        a.copy('expired');
        await until(() => broker.held == 1);
        jump = const Duration(seconds: 20);
        broker.hold!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(b.text, isNot('expired'));
        a.copy('fresh');
        await until(() => b.text == 'fresh');
      } finally {
        if (broker.hold?.isCompleted == false) broker.hold!.complete();
        await ea.stop();
        await eb.stop();
      }
    },
  );

  test(
    'network failure clears pending copies and reconnect establishes a new baseline',
    () async {
      final broker = _Broker(), a = _Clipboard(), b = _Clipboard();
      final sa = <ClipboardSyncStatus>[], sb = <ClipboardSyncStatus>[];
      ClipboardSyncEngine make(
        String id,
        String peer,
        _Clipboard cb,
        List<ClipboardSyncStatus> states,
      ) => ClipboardSyncEngine(
        config: _config(id, peer),
        clipboard: cb,
        onStatus: states.add,
        transport: broker.create,
        pollInterval: const Duration(milliseconds: 10),
        helloInterval: const Duration(seconds: 1),
      );
      final ea = make('a', 'b', a, sa), eb = make('b', 'a', b, sb);
      Future<void> until(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 6));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Reconnect timed out: A=${sa.last.phase}/${sa.last.peers}/${sa.last.sent}, B=${sb.last.phase}/${sb.last.peers}/${sb.last.sent}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      try {
        await ea.start();
        await eb.start();
        await until(() => sa.last.peers == 1 && sb.last.peers == 1);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        broker.failData = true;
        a.copy('failed');
        await until(() => sa.last.phase == 'reconnecting');
        a.copy('offline newest');
        broker.failData = false;
        await until(() => sa.last.peers == 1 && sa.last.phase == 'running');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(b.text, 'existing clipboard');
        a.copy('after reconnect');
        await until(() => b.text == 'after reconnect');
        expect(sa.last.sent, 1);
      } finally {
        await ea.stop();
        await eb.stop();
      }
    },
  );
}
