import 'dart:convert';
import 'gotify_models.dart';

const maxRealtimeTextBytes = 32 * 1024;

enum RealtimeTextFailure {
  notReady,
  empty,
  tooLarge,
  queueFull,
  sendFailed,
  uncertain,
}

class RealtimeTextException implements Exception {
  const RealtimeTextException(this.failure);
  final RealtimeTextFailure failure;
}

enum RealtimeTextStatus { received, sending, sent, failed, uncertain }

class GotifyTextMessage {
  const GotifyTextMessage({
    required this.event,
    required this.isLocal,
    required this.status,
    this.failure,
  });
  final RemoteSendEvent event;
  final bool isLocal;
  final RealtimeTextStatus status;
  final RealtimeTextFailure? failure;
  String get id => event.eventId;
  String get content => event.payload['content'] as String;
  GotifyTextMessage withResult(
    RealtimeTextStatus status, [
    RealtimeTextFailure? failure,
  ]) => GotifyTextMessage(
    event: event,
    isLocal: isLocal,
    status: status,
    failure: failure,
  );
}

bool isValidRealtimeText(RemoteSendEvent event) {
  final content = event.payload['content'];
  return event.type == RemoteSendEvent.textDirect &&
      event.payload['contentType'] == 'text/plain' &&
      content is String &&
      content.trim().isNotEmpty &&
      utf8.encode(content).length <= maxRealtimeTextBytes;
}

/// Connection identity, not registration/target/UI preferences.
Object gotifyTextIdentity(GotifyConfig config) => (
  config.serverUrl.trim(),
  config.appToken.trim(),
  config.clientToken.trim(),
  config.deviceId,
);
