import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/services/opened_file_service.dart';

void main() {
  test('decodes imported paths and permission/storage failures', () {
    expect(
      OpenedFileEvent.fromPlatform({
        'id': 'one',
        'path': '/stage/report.pdf',
      }).path,
      '/stage/report.pdf',
    );
    expect(
      OpenedFileEvent.fromPlatform({
        'id': 'two',
        'error': 'permission_denied',
      }).error,
      OpenedFileError.permissionDenied,
    );
    expect(
      OpenedFileEvent.fromPlatform({
        'id': 'three',
        'error': 'unavailable',
      }).error,
      OpenedFileError.unavailable,
    );
    expect(
      OpenedFileEvent.fromPlatform({'id': 'four', 'error': 'failed'}).error,
      OpenedFileError.failed,
    );
  });

  test('malformed events cannot create empty pending paths', () {
    expect(() => OpenedFileEvent.fromPlatform(null), throwsFormatException);
    expect(
      () => OpenedFileEvent.fromPlatform({'id': ''}),
      throwsFormatException,
    );
    expect(
      OpenedFileEvent.fromPlatform({'id': 'empty', 'path': ''}).error,
      OpenedFileError.failed,
    );
  });

  testWidgets(
    'one subscription receives buffered cold-start and later warm-start events',
    (tester) async {
      const name = 'remote_send/opened_files';
      const codec = StandardMethodCodec();
      final calls = <String>[];
      void emit(Map<String, String> event) {
        tester.binding.channelBuffers.push(
          name,
          codec.encodeSuccessEnvelope(event),
          (_) {},
        );
      }

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(name),
        (call) async {
          calls.add(call.method);
          if (call.method == 'listen') {
            emit({'id': 'cold', 'path': '/stage/cold.pdf'});
          }
          return null;
        },
      );
      final received = <OpenedFileEvent>[];
      final subscription = OpenedFileService().events.listen(received.add);
      try {
        await tester.pump();
        emit({'id': 'warm', 'path': '/stage/warm.png'});
        await tester.pump();
        expect(received.map((event) => event.id), ['cold', 'warm']);
        expect(received.map((event) => event.path), [
          '/stage/cold.pdf',
          '/stage/warm.png',
        ]);
        expect(calls, ['listen']);
      } finally {
        unawaited(subscription.cancel());
        await tester.pump();
        expect(calls, ['listen', 'cancel']);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(name),
          null,
        );
      }
    },
  );
}
