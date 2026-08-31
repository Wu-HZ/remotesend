import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/providers/gotify_coordinator_provider.dart';

void main() {
  test('selects only the newest available newly-received text', () {
    final older = RemoteSendEvent(
      type: RemoteSendEvent.textChanged,
      eventId: 'event-1',
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
      payload: const {RemoteSendEvent.newMessageIdPayloadKey: 'message-1'},
      createdAt: DateTime.utc(2026, 8, 31, 12),
    );
    final newer = RemoteSendEvent(
      type: RemoteSendEvent.textChanged,
      eventId: 'event-2',
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
      payload: const {RemoteSendEvent.newMessageIdPayloadKey: 'message-2'},
      createdAt: DateTime.utc(2026, 8, 31, 12, 1),
    );
    final deletion = RemoteSendEvent(
      type: RemoteSendEvent.textChanged,
      eventId: 'event-3',
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
      createdAt: DateTime.utc(2026, 8, 31, 12, 2),
    );

    expect(
      selectNewestTextForClipboard(
        [older, newer, deletion],
        const {'message-1': 'first', 'message-2': 'second'},
      ),
      'second',
    );
  });

  test('does not copy deletion events or messages no longer on WebDAV', () {
    final removed = RemoteSendEvent(
      type: RemoteSendEvent.textChanged,
      eventId: 'event-1',
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
      payload: const {RemoteSendEvent.newMessageIdPayloadKey: 'removed'},
    );
    final deletion = RemoteSendEvent(
      type: RemoteSendEvent.textChanged,
      eventId: 'event-2',
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
    );

    expect(selectNewestTextForClipboard([removed, deletion], const {}), isNull);
  });
}
