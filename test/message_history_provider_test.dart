import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/providers/message_history_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/services/webdav_exceptions.dart';
import 'package:remote_send/services/webdav_service.dart';

class _FakeWebDavService extends WebDavService {
  _FakeWebDavService(this.content);

  final String content;
  int readCount = 0;

  @override
  Future<WebDavResult<String>> readMessagesFile(String date) async {
    readCount++;
    return WebDavResult.success(content);
  }
}

void main() {
  test('remote text refresh can read a non-active WebDAV service', () async {
    final activeService = _FakeWebDavService('[]');
    final sourceService = _FakeWebDavService('''
[
  {
    "id": "message-1",
    "content": "from another server",
    "senderName": "Phone A",
    "isLocal": false,
    "timestamp": "2026-09-01T12:00:00.000Z"
  }
]
''');
    final container = ProviderContainer(
      overrides: [webDavTextServiceProvider.overrideWithValue(activeService)],
    );
    addTearDown(container.dispose);

    final messages = await container
        .read(messageHistoryProvider.notifier)
        .refreshFromRemoteChange(
          '2026-09-01',
          serviceOverride: sourceService,
          updateUi: false,
        );

    expect(activeService.readCount, 0);
    expect(sourceService.readCount, 1);
    expect(messages?.single.content, 'from another server');
    expect(container.read(messageHistoryProvider).messages, isEmpty);
  });
}
