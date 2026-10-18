import 'package:flutter/services.dart';

enum OpenedFileError { permissionDenied, unavailable, failed }

class OpenedFileEvent {
  const OpenedFileEvent({required this.id, this.path, this.error});

  final String id;
  final String? path;
  final OpenedFileError? error;

  factory OpenedFileEvent.fromPlatform(Object? event) {
    if (event is! Map ||
        event['id'] is! String ||
        (event['id'] as String).isEmpty) {
      throw const FormatException('Invalid opened-file event');
    }
    final path = event['path'];
    if (path is String && path.isNotEmpty) {
      return OpenedFileEvent(id: event['id'] as String, path: path);
    }
    return OpenedFileEvent(
      id: event['id'] as String,
      error: switch (event['error']) {
        'permission_denied' => OpenedFileError.permissionDenied,
        'unavailable' => OpenedFileError.unavailable,
        _ => OpenedFileError.failed,
      },
    );
  }
}

/// Native code buffers cold-start imports until this stream is subscribed and
/// emits later ACTION_VIEW imports through the same stream on warm starts.
class OpenedFileService {
  static const _channel = EventChannel('remote_send/opened_files');
  Stream<OpenedFileEvent>? _events;

  Stream<OpenedFileEvent> get events => _events ??= _channel
      .receiveBroadcastStream()
      .map(OpenedFileEvent.fromPlatform);
}
