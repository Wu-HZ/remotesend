import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/models/gotify_text_message.dart';
import 'package:remote_send/providers/app_visibility_provider.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/gotify_provider.dart';
import 'package:remote_send/providers/gotify_text_session_provider.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/gotify_service.dart';
import 'package:remote_send/services/gotify_runtime_store.dart';
import 'package:remote_send/services/text_clipboard_service.dart';

class _Store extends ConfigService {
  @override
  Future<bool> saveConfig(AppConfig config) async => true;
}

class _Config extends ConfigNotifier {
  _Config() : super(_Store()) {
    state = AsyncData(
      AppConfig(
        gotify: GotifyConfig(
          enabled: true,
          registerAsTextServer: true,
          serverUrl: 'https://gotify.invalid',
          appToken: 'app',
          clientToken: 'client',
          deviceId: 'local',
        ),
      ),
    );
  }
}

class _Clipboard extends TextClipboardService {
  final writes = <String>[];
  @override
  Future<void> writeText(String text) async {
    writes.add(text);
  }
}

GotifyMessage envelope(RemoteSendEvent event, {int id = 100, int app = 7}) =>
    GotifyMessage(
      id: id,
      applicationId: app,
      title: 'text',
      message: 'generic',
      date: DateTime.now(),
      extras: event.toExtras(),
    );
RemoteSendEvent direct(
  String content, {
  String? id,
  List<String> targets = const [],
  DateTime? createdAt,
}) => RemoteSendEvent(
  type: RemoteSendEvent.textDirect,
  senderDeviceId: 'remote',
  senderName: 'Phone',
  eventId: id,
  targetDeviceIds: targets,
  createdAt: createdAt,
  payload: {'contentType': 'text/plain', 'content': content},
);

class _Service extends GotifyService {
  _Service(super.config);
  final controller = StreamController<GotifyMessage>.broadcast();
  final sent = <RemoteSendEvent>[];
  List<GotifyMessage> history = [];
  GotifyMessage? liveDuringFetch;
  Completer<void>? gate;
  String? failCode;
  @override
  Stream<GotifyMessage> get messages => controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<GotifyMessagePage> fetchMessages({int limit = 200, int? since}) async {
    if (liveDuringFetch case final live?) {
      controller.add(live);
      liveDuringFetch = null;
    }
    return GotifyMessagePage(messages: history);
  }

  @override
  Future<GotifyMessage> send({
    required RemoteSendEvent event,
    required String title,
    required String message,
    int priority = 0,
  }) async {
    sent.add(event);
    if (event.type == RemoteSendEvent.textDirect) {
      await gate?.future;
      if (failCode != null) throw GotifyException('redacted', code: failCode);
    }
    return envelope(event, id: sent.length);
  }

  @override
  Future<void> close() async {
    if (!controller.isClosed) await controller.close();
  }
}

class _Harness {
  _Harness({void Function(_Service)? setup}) {
    container = ProviderContainer(
      overrides: [
        configProvider.overrideWith((ref) => config),
        textClipboardServiceProvider.overrideWithValue(clipboard),
        realtimeTextClockProvider.overrideWithValue(() => now),
        gotifyServiceFactoryProvider.overrideWithValue((config) {
          service = _Service(config);
          setup?.call(service);
          return service;
        }),
      ],
    );
    session = container.read(gotifyTextSessionProvider.notifier);
    final gotify = container.read(gotifyProvider.notifier);
    subscription = gotify.events.listen((event) {
      if (event.type == RemoteSendEvent.textDirect) session.receive(event);
    });
  }
  final config = _Config();
  final clipboard = _Clipboard();
  DateTime now = DateTime.utc(2026, 9, 1);
  late final ProviderContainer container;
  late _Service service;
  late final GotifyTextSessionNotifier session;
  late final StreamSubscription<RemoteSendEvent> subscription;
  Future<void> ready() async {
    for (
      var i = 0;
      i < 100 && !container.read(gotifyProvider).isConnected;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(container.read(gotifyProvider).isConnected, isTrue);
  }

  Future<void> configure(GotifyConfig next) async {
    await config.updateConfig(config.state.requireValue.copyWith(gotify: next));
  }

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));
  Future<void> dispose() async {
    if (service.gate case final gate?) {
      if (!gate.isCompleted) gate.complete();
    }
    await subscription.cancel();
    container.dispose();
    await tick();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'connection identity changes clear RAM and stale callbacks cannot restore old text',
    () async {
      final h = _Harness();
      try {
        await h.ready();
        final oldService = h.service;
        oldService.gate = Completer<void>();
        final send = h.session.send('old-account-body');
        await h.configure(
          h.config.state.requireValue.gotify.copyWith(
            appToken: 'new-app-token',
          ),
        );
        expect(await send, isFalse);
        await h.ready();
        oldService.gate!.complete();
        await h.tick();
        expect(h.session.state.messages, isEmpty);
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'direct send serializes bodies without WebDAV or persisted outbox',
    () async {
      final h = _Harness();
      try {
        await h.ready();
        h.service.gate = Completer<void>();
        final first = h.session.send('SECRET_DIRECT_ONE\n你好');
        final second = h.session.send('SECRET_DIRECT_TWO');
        expect(
          h.service.sent.where((e) => e.type == RemoteSendEvent.textDirect),
          hasLength(1),
        );
        h.service.gate!.complete();
        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(h.session.state.messages.map((m) => m.content), [
          'SECRET_DIRECT_ONE\n你好',
          'SECRET_DIRECT_TWO',
        ]);
        expect(
          h.session.state.messages.every(
            (m) => m.status == RealtimeTextStatus.sent,
          ),
          isTrue,
        );
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs
            .getKeys()
            .map((key) => prefs.get(key).toString())
            .join();
        expect(stored, isNot(contains('SECRET_DIRECT')));
        expect(h.container.read(gotifyProvider).outboxCount, 0);
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'backfill is ignored while an identical buffered live frame is delivered once',
    () async {
      final event = direct('live body', id: 'shared');
      final h = _Harness(
        setup: (service) {
          service.history = [
            envelope(direct('old history', id: 'old'), id: 90),
            envelope(event),
          ];
          service.liveDuringFetch = envelope(event);
        },
      );
      try {
        await h.ready();
        await h.tick();
        expect(h.session.state.messages.map((m) => m.content), ['live body']);
        h.service.controller.add(envelope(event));
        await h.tick();
        expect(h.session.state.messages, hasLength(1));
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'incoming direct messages filter application, targets, self, malformed bodies and duplicates',
    () async {
      final h = _Harness();
      try {
        await h.ready();
        final event = direct('valid', id: 'same');
        h.service.controller.add(envelope(event, app: 99));
        h.service.controller.add(envelope(event));
        h.service.controller.add(envelope(event));
        h.service.controller.add(
          envelope(direct('wrong target', targets: ['someone-else'])),
        );
        h.service.controller.add(
          envelope(
            RemoteSendEvent(
              type: RemoteSendEvent.textDirect,
              senderDeviceId: 'local',
              senderName: 'me',
              payload: {'contentType': 'text/plain', 'content': 'self'},
            ),
          ),
        );
        h.service.controller.add(
          envelope(direct('x' * (maxRealtimeTextBytes + 1))),
        );
        await h.tick();
        expect(h.session.state.messages.map((m) => m.content), ['valid']);
        h.service.controller.add(envelope(direct('valid', id: 'different')));
        await h.tick();
        expect(h.session.state.messages, hasLength(2));
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'timeouts are uncertain and manual retry reuses the same message ID',
    () async {
      final h = _Harness();
      try {
        await h.ready();
        h.service.failCode = 'timeout';
        expect(await h.session.send('retry me'), isFalse);
        final failed = h.session.state.messages.single;
        expect(failed.status, RealtimeTextStatus.uncertain);
        h.service.failCode = null;
        expect(
          await h.session.send(failed.content, retryId: failed.id),
          isTrue,
        );
        final sent = h.service.sent
            .where((e) => e.type == RemoteSendEvent.textDirect)
            .toList();
        expect(sent[0].eventId, sent[1].eventId);
        expect(h.session.state.messages, hasLength(1));
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'registration toggle cancels queued jobs and clears RAM without rebuilding Gotify connection',
    () async {
      final h = _Harness();
      try {
        await h.ready();
        final connection = h.container.read(gotifyProvider.notifier);
        h.service.gate = Completer<void>();
        final first = h.session.send('in-flight');
        final second = h.session.send('queued');
        await h.configure(
          h.config.state.requireValue.gotify.copyWith(
            registerAsTextServer: false,
          ),
        );
        expect(await first, isFalse);
        expect(await second, isFalse);
        expect(h.session.state.messages, isEmpty);
        expect(h.container.read(gotifyProvider.notifier), same(connection));
        h.service.gate!.complete();
        await h.tick();
        expect(
          h.service.sent.where((e) => e.type == RemoteSendEvent.textDirect),
          hasLength(1),
        );
        expect(h.session.state.messages, isEmpty);
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'background text stays in RAM, expires by local receipt time, and copies only newest accepted text',
    () async {
      final h = _Harness();
      try {
        await h.ready();
        await h.configure(
          h.config.state.requireValue.gotify.copyWith(
            receiveTextInBackground: false,
            autoCopyTextEnabled: true,
          ),
        );
        h.container.read(appForegroundProvider.notifier).state = false;
        h.service.controller.add(
          envelope(direct('SECRET_BACKGROUND', createdAt: DateTime.utc(2099))),
        );
        await h.tick();
        expect(h.session.state.messages, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().map((key) => prefs.get(key).toString()).join(),
          isNot(contains('SECRET_BACKGROUND')),
        );
        h.now = h.now.add(const Duration(minutes: 4));
        h.container.read(appForegroundProvider.notifier).state = true;
        expect(h.session.state.messages, isEmpty);
        expect(h.session.state.droppedCount, 1);
        h.session.receive(direct('first'));
        h.session.receive(direct('second'));
        await h.tick();
        expect(h.session.state.messages, hasLength(2));
        expect(h.clipboard.writes, ['second']);
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'session and pending queue are bounded; invalid and oversized messages are rejected',
    () async {
      final h = _Harness();
      try {
        await h.ready();
        expect(await h.session.send('  '), isFalse);
        expect(await h.session.send('你' * maxRealtimeTextBytes), isFalse);
        for (var i = 0; i < 210; i++) {
          h.session.receive(direct('message $i'));
        }
        expect(h.session.state.messages, hasLength(200));
        h.service.gate = Completer<void>();
        final sends = [
          for (var i = 0; i < 100; i++) h.session.send('queued $i'),
        ];
        expect(await h.session.send('overflow'), isFalse);
        expect(h.session.state.failure, RealtimeTextFailure.queueFull);
        await h.configure(
          h.config.state.requireValue.gotify.copyWith(
            registerAsTextServer: false,
          ),
        );
        expect((await Future.wait(sends)).every((success) => !success), isTrue);
      } finally {
        await h.dispose();
      }
    },
  );

  test(
    'runtime store defensively excludes direct bodies from legacy persistence',
    () {
      final event = direct('never persist');
      final runtime = GotifyRuntimeData(
        deferredInboundEvents: [event],
        outbox: [
          PendingGotifyEvent(
            event: event,
            title: 't',
            message: 'm',
            priority: 1,
          ),
        ],
      );
      expect(jsonEncode(runtime.toJson()), isNot(contains('never persist')));
      final loaded = GotifyRuntimeData.fromJson({
        'deferredInboundEvents': [event.toJson()],
        'outbox': [
          PendingGotifyEvent(
            event: event,
            title: 't',
            message: 'm',
            priority: 1,
          ).toJson(),
        ],
      });
      expect(loaded.deferredInboundEvents, isEmpty);
      expect(loaded.outbox, isEmpty);
    },
  );
}
