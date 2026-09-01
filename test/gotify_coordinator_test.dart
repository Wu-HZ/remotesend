import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/providers/gotify_coordinator_provider.dart';

void main() {
  test('defers background events using independent text and file policies', () {
    final text = RemoteSendEvent(
      type: RemoteSendEvent.textChanged,
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
    );
    final file = RemoteSendEvent(
      type: RemoteSendEvent.fileReady,
      senderDeviceId: 'device-a',
      senderName: 'Phone A',
    );
    final defaults = GotifyConfig();

    expect(
      shouldDeferRemoteEventInBackground(text, defaults, isForeground: false),
      isFalse,
    );
    expect(
      shouldDeferRemoteEventInBackground(file, defaults, isForeground: false),
      isTrue,
    );
    expect(
      shouldDeferRemoteEventInBackground(file, defaults, isForeground: true),
      isFalse,
    );
    expect(
      shouldDeferRemoteEventInBackground(
        text,
        defaults.copyWith(receiveTextInBackground: false),
        isForeground: false,
      ),
      isTrue,
    );
  });

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
