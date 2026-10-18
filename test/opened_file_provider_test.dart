import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/providers/opened_file_provider.dart';
import 'package:remote_send/providers/pending_upload_provider.dart';
import 'package:remote_send/providers/upload_queue_provider.dart';
import 'package:remote_send/services/opened_file_service.dart';
import 'package:remote_send/services/webdav_service.dart';

class _Service extends OpenedFileService {
  final controller = StreamController<OpenedFileEvent>.broadcast(sync: true);
  @override
  Stream<OpenedFileEvent> get events => controller.stream;
}

void main() {
  late _Service service;
  late ProviderContainer container;
  late int uploadQueuesCreated;

  setUp(() {
    service = _Service();
    uploadQueuesCreated = 0;
    container = ProviderContainer(
      overrides: [
        openedFileSupportedProvider.overrideWithValue(true),
        openedFileServiceProvider.overrideWithValue(service),
        uploadQueueProvider.overrideWith((ref) {
          uploadQueuesCreated++;
          return UploadQueueNotifier(WebDavService(), ref);
        }),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await service.controller.close();
  });

  test(
    'cold and warm file imports append to pending without starting uploads',
    () {
      container.read(pendingUploadProvider.notifier).addFiles([
        '/already-pending.txt',
      ]);
      final notifier = container.read(openedFileProvider.notifier)
        ..initialize();
      service.controller.add(
        const OpenedFileEvent(id: 'cold', path: '/staged/report.pdf'),
      );
      service.controller.add(
        const OpenedFileEvent(id: 'warm', path: '/staged/image.png'),
      );
      expect(container.read(pendingUploadProvider).filePaths, [
        '/already-pending.txt',
        '/staged/report.pdf',
        '/staged/image.png',
      ]);
      expect(notifier.state.openedCount, 2);
      expect(uploadQueuesCreated, 0);
    },
  );

  test(
    'initialization and duplicate deliveries cannot add the same import twice',
    () {
      final notifier = container.read(openedFileProvider.notifier);
      notifier.initialize();
      notifier.initialize();
      const event = OpenedFileEvent(id: 'one', path: '/staged/report.pdf');
      service.controller.add(event);
      service.controller.add(event);
      expect(container.read(pendingUploadProvider).filePaths, [event.path]);
      expect(notifier.state.openedCount, 1);
    },
  );

  test('a separate open of the same file is a new import', () {
    container.read(openedFileProvider.notifier).initialize();
    service.controller.add(
      const OpenedFileEvent(id: 'one', path: '/stage/one/report.txt'),
    );
    service.controller.add(
      const OpenedFileEvent(id: 'two', path: '/stage/two/report.txt'),
    );
    expect(container.read(pendingUploadProvider).filePaths, hasLength(2));
  });

  test(
    'imports arriving during submission remain in the next pending batch',
    () {
      final pending = container.read(pendingUploadProvider.notifier);
      pending.addFiles(['/sending.txt']);
      final batch = pending.beginSubmission();
      container.read(openedFileProvider.notifier).initialize();
      service.controller.add(
        const OpenedFileEvent(id: 'new', path: '/new.txt'),
      );
      expect(batch, ['/sending.txt']);
      expect(pending.state.filePaths, ['/new.txt']);
      expect(pending.state.isSubmitting, isTrue);
      pending.finishSubmission();
      expect(pending.state.filePaths, ['/new.txt']);
    },
  );

  test(
    'missing grants and files report errors without adding broken tasks',
    () {
      final notifier = container.read(openedFileProvider.notifier)
        ..initialize();
      service.controller.add(
        const OpenedFileEvent(
          id: 'denied',
          error: OpenedFileError.permissionDenied,
        ),
      );
      expect(notifier.state.error, OpenedFileError.permissionDenied);
      service.controller.add(
        const OpenedFileEvent(id: 'gone', error: OpenedFileError.unavailable),
      );
      expect(notifier.state.errorRevision, 2);
      expect(notifier.state.error, OpenedFileError.unavailable);
      expect(container.read(pendingUploadProvider).filePaths, isEmpty);
      expect(uploadQueuesCreated, 0);
      service.controller.add(
        const OpenedFileEvent(id: 'ok', path: '/valid.txt'),
      );
      expect(notifier.state.error, isNull);
      expect(notifier.state.openedCount, 1);
    },
  );

  test('stream failures are handled and later valid imports still work', () {
    final notifier = container.read(openedFileProvider.notifier)..initialize();
    service.controller.addError(const FormatException('bad event'));
    expect(notifier.state.error, OpenedFileError.failed);
    service.controller.add(const OpenedFileEvent(id: 'ok', path: '/valid.txt'));
    expect(notifier.state.openedCount, 1);
  });

  test(
    'non-Android platforms do not subscribe to the native channel',
    () async {
      final other = ProviderContainer(
        overrides: [
          openedFileSupportedProvider.overrideWithValue(false),
          openedFileServiceProvider.overrideWithValue(service),
        ],
      );
      try {
        other.read(openedFileProvider.notifier).initialize();
        expect(service.controller.hasListener, isFalse);
      } finally {
        other.dispose();
      }
    },
  );
}
