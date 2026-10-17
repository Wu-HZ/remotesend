import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/services/clipboard_auto_send_session.dart';

class _Harness {
  String? text = 'already copied';
  String? internalText;
  bool busy = false;
  bool readable = true;
  bool failRead = false;
  bool failSend = false;
  Future<String?> Function()? reader;
  Future<bool> Function(String)? sender;
  final sent = <String>[];
  final errors = <ClipboardAutoSendError>[];

  late final session = ClipboardAutoSendSession(
    readText: () async {
      if (failRead) throw StateError('clipboard unavailable');
      return reader == null ? text : await reader!();
    },
    sendText: (text) async {
      sent.add(text);
      return sender == null ? !failSend : await sender!(text);
    },
    canSend: () => !busy,
    canRead: () => readable,
    isInternalText: (text) => text == internalText,
    onError: errors.add,
  );
}

const _tick = Duration(milliseconds: 500);

void main() {
  testWidgets('defaults off and starts with a baseline, not a send', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    expect(h.session.isActive, isFalse);
    await tester.pump(_tick);
    expect(h.sent, isEmpty);
    await h.session.start();
    await tester.pump(_tick);
    expect(h.session.isActive, isTrue);
    expect(h.sent, isEmpty);
    h.text = 'new text';
    await tester.pump(_tick);
    expect(h.sent, ['new text']);
    h.session.stop();
  });

  testWidgets('ignores empty, non-text and unchanged clipboard data', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    await h.session.start();
    for (final text in [null, '', '   ', ' first ', 'first', 'first']) {
      h.text = text;
      await tester.pump(_tick);
    }
    expect(h.sent, ['first']);
    h.text = 'second';
    await tester.pump(_tick);
    h.text = 'first';
    await tester.pump(_tick);
    expect(h.sent, ['first', 'second', 'first']);
    h.session.stop();
  });

  testWidgets('queues copies during a slow upload and sends serially', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    final upload = Completer<bool>();
    h.sender = (_) => upload.future;
    await h.session.start();
    h.text = 'first';
    await tester.pump(_tick);
    h.text = 'second';
    await tester.pump(_tick);
    h.text = 'third';
    await tester.pump(_tick);
    expect(h.sent, ['first']);
    h.sender = (_) async => true;
    upload.complete(true);
    await tester.pump();
    expect(h.sent, ['first', 'second', 'third']);
    h.session.stop();
  });

  testWidgets('waits for a manual send without losing copies', (tester) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    await h.session.start();
    h.busy = true;
    h.text = 'first';
    await tester.pump(_tick);
    h.text = 'second';
    await tester.pump(_tick);
    expect(h.sent, isEmpty);
    h.busy = false;
    await tester.pump(_tick);
    expect(h.sent, ['first', 'second']);
    h.session.stop();
  });

  testWidgets(
    'ignores received or manually copied app text to prevent echoes',
    (tester) async {
      final h = _Harness();
      addTearDown(h.session.dispose);
      await h.session.start();
      h.text = h.internalText = 'remote message';
      await tester.pump(_tick);
      expect(h.sent, isEmpty);
      h.text = 'external copy';
      await tester.pump(_tick);
      expect(h.sent, ['external copy']);
      h.session.stop();
    },
  );

  testWidgets(
    'stop discards queued data but permits an in-flight send to finish',
    (tester) async {
      final h = _Harness();
      addTearDown(h.session.dispose);
      final upload = Completer<bool>();
      h.sender = (_) => upload.future;
      await h.session.start();
      h.text = 'first';
      await tester.pump(_tick);
      h.text = 'queued';
      await tester.pump(_tick);
      h.session.stop();
      upload.complete(true);
      h.text = 'after stop';
      await tester.pump(_tick);
      expect(h.session.isActive, isFalse);
      expect(h.sent, ['first']);
    },
  );

  testWidgets('late baseline from a stopped session cannot affect a new one', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    final oldRead = Completer<String?>();
    h.reader = () => oldRead.future;
    final oldStart = h.session.start();
    h.session.stop();
    h.reader = null;
    await h.session.start();
    oldRead.complete('old baseline');
    await oldStart;
    await tester.pump(_tick);
    expect(h.sent, isEmpty);
    h.session.stop();
  });

  testWidgets('stop during an asynchronous clipboard read prevents sending', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    await h.session.start();
    final read = Completer<String?>();
    h.reader = () => read.future;
    await tester.pump(_tick);
    h.session.stop();
    read.complete('too late');
    await tester.pump();
    expect(h.sent, isEmpty);
  });

  testWidgets('a new session never overlaps a previous in-flight upload', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    final upload = Completer<bool>();
    h.sender = (_) => upload.future;
    await h.session.start();
    h.text = 'old';
    await tester.pump(_tick);
    h.session.stop();
    await h.session.start();
    h.text = 'new';
    await tester.pump(_tick);
    expect(h.sent, ['old']);
    h.sender = (_) async => true;
    upload.complete(false); // Must not stop the new session.
    await tester.pump(_tick);
    expect(h.session.isActive, isTrue);
    expect(h.sent, ['old', 'new']);
    expect(h.errors, isEmpty);
    h.session.stop();
  });

  testWidgets('mobile background policy defers reads until foreground', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    await h.session.start();
    h.readable = false;
    h.text = 'copied in another app';
    await tester.pump(_tick);
    expect(h.sent, isEmpty);
    h.readable = true;
    await tester.pump(_tick);
    expect(h.sent, ['copied in another app']);
    h.session.stop();
  });

  testWidgets('read errors stop the session instead of repeatedly prompting', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    await h.session.start();
    h.failRead = true;
    await tester.pump(_tick);
    await tester.pump(_tick);
    expect(h.session.isActive, isFalse);
    expect(h.errors, [ClipboardAutoSendError.read]);
  });

  testWidgets('baseline errors also stop the session', (tester) async {
    final h = _Harness()..failRead = true;
    addTearDown(h.session.dispose);
    await h.session.start();
    expect(h.session.isActive, isFalse);
    expect(h.errors, [ClipboardAutoSendError.read]);
  });

  testWidgets('send failures stop and discard the remaining queue', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.session.dispose);
    await h.session.start();
    h.busy = true;
    h.text = 'first';
    await tester.pump(_tick);
    h.text = 'second';
    await tester.pump(_tick);
    h.busy = false;
    h.failSend = true;
    await tester.pump(_tick);
    expect(h.sent, ['first']);
    expect(h.errors, [ClipboardAutoSendError.send]);
    expect(h.session.isActive, isFalse);
  });

  testWidgets('dispose cancels polling', (tester) async {
    final h = _Harness();
    await h.session.start();
    h.session.dispose();
    h.text = 'after disposal';
    await tester.pump(_tick);
    expect(h.sent, isEmpty);
  });
}
