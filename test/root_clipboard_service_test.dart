import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/root_clipboard.dart';
import 'package:remote_send/services/root_clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('remote_send/root_clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? reply;
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'constructing service does not request root; start validates shell identity',
    () async {
      final service = RootClipboardService();
      expect(calls, isEmpty);
      reply = {
        'session': 1,
        'sdk': 35,
        'uid': 2000,
        'userId': 0,
        'api': 'ATTRIBUTION_USER_DEVICE',
      };
      final info = await service.start();
      expect(info.uid, 2000);
      expect(info.session, 1);
      expect(calls.single.method, 'start');
      reply = {
        'session': 1,
        'sdk': 35,
        'uid': 0,
        'userId': 0,
        'api': 'ATTRIBUTION_USER_DEVICE',
      };
      await expectLater(service.start(), throwsFormatException);
    },
  );

  test(
    'write passes raw text as data, preserving Unicode and whitespace',
    () async {
      const text = '  中文 ✓\n  ';
      reply = {
        'kind': 'text',
        'bytes': utf8.encode(text).length,
        'internal': true,
        'text': text,
      };
      final snapshot = await RootClipboardService().writeText(text);
      expect(snapshot.text, text);
      expect(snapshot.metadata.internal, isTrue);
      expect(calls.single.method, 'write');
      expect(calls.single.arguments, {'text': text});
    },
  );

  test('empty and oversized writes never reach native code', () {
    final service = RootClipboardService();
    expect(() => service.writeText(''), throwsArgumentError);
    expect(() => service.writeText('x' * 32769), throwsArgumentError);
    expect(() => service.writeText('你' * 11000), throwsArgumentError);
    expect(calls, isEmpty);
  });

  test('sensitive metadata never accepts an attached body', () async {
    reply = {'kind': 'sensitive', 'internal': false};
    final service = RootClipboardService();
    final snapshot = await service.read();
    expect(snapshot.metadata.kind, RootClipboardKind.sensitive);
    expect(snapshot.text, isNull);
    reply = {'kind': 'sensitive', 'internal': false, 'text': 'secret'};
    await expectLater(service.read(), throwsFormatException);
  });

  test(
    'invalid sizes, text mismatches and unknown kinds fail closed',
    () async {
      final service = RootClipboardService();
      for (final map in [
        {'kind': 'text', 'internal': false, 'bytes': -1, 'text': 'x'},
        {'kind': 'text', 'internal': false, 'bytes': 4, 'text': 'x'},
        {'kind': 'text', 'internal': false, 'bytes': 1},
        {'kind': 'unknown', 'internal': false},
      ]) {
        reply = map;
        await expectLater(service.read(), throwsFormatException);
      }
    },
  );

  test('event parser retains metadata only and session identity', () {
    final event = RootClipboardEvent.fromMap({
      'event': 'clipboard',
      'session': 3,
      'snapshot': {
        'kind': 'text',
        'bytes': 6,
        'internal': false,
        'text': 'not retained',
      },
    });
    expect(event.session, 3);
    expect(event.metadata!.bytes, 6);
    expect(event.metadata, isA<RootClipboardMetadata>());
    expect(
      () => RootClipboardEvent.fromMap({'event': 'unknown', 'session': 3}),
      throwsFormatException,
    );
  });

  test('stop does not launch or authorize a helper', () async {
    reply = null;
    await RootClipboardService().stop();
    expect(calls.single.method, 'stop');
  });
}
