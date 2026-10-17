import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/services/text_clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late TextClipboardService service;
  String? clipboard;
  bool failWrite = false;
  Completer<Object?>? delayedRead;

  setUp(() {
    service = TextClipboardService();
    clipboard = null;
    failWrite = false;
    delayedRead = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return delayedRead?.future ?? {'text': clipboard};
        case 'Clipboard.setData':
          if (failWrite) throw PlatformException(code: 'denied');
          clipboard = (call.arguments as Map)['text'] as String;
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('app writes are marked and external copies are not', () async {
    await service.writeText(' received text ');
    expect(await service.readText(), ' received text ');
    expect(service.isInternalText('received text'), isTrue);
    clipboard = 'external';
    expect(await service.readText(), 'external');
    expect(service.isInternalText('external'), isFalse);
    // Copying the former app text again after an external change is allowed.
    clipboard = 'received text';
    await service.readText();
    expect(service.isInternalText('received text'), isFalse);
  });

  test('failed writes do not suppress a later external copy', () async {
    failWrite = true;
    await expectLater(
      service.writeText('failed'),
      throwsA(isA<PlatformException>()),
    );
    clipboard = 'failed';
    await service.readText();
    expect(service.isInternalText('failed'), isFalse);
  });

  test(
    'a delayed clipboard read cannot erase a newer app write marker',
    () async {
      delayedRead = Completer<Object?>();
      final read = service.readText();
      await service.writeText('received');
      delayedRead!.complete({'text': 'old clipboard'});
      await read;
      expect(service.isInternalText('received'), isTrue);
    },
  );
}
