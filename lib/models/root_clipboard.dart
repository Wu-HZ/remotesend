/// Diagnostics deliberately keep metadata separate from clipboard bodies.
enum RootClipboardKind {
  text,
  empty,
  nonText,
  sensitive,
  tooLarge,
  unavailable,
}

class RootClipboardMetadata {
  const RootClipboardMetadata({
    required this.kind,
    this.bytes,
    this.internal = false,
  });
  final RootClipboardKind kind;
  final int? bytes;
  final bool internal;

  factory RootClipboardMetadata.fromMap(Map<Object?, Object?> map) {
    final kind = switch (map['kind']) {
      'text' => RootClipboardKind.text,
      'empty' => RootClipboardKind.empty,
      'non_text' => RootClipboardKind.nonText,
      'sensitive' => RootClipboardKind.sensitive,
      'too_large' => RootClipboardKind.tooLarge,
      'unavailable' => RootClipboardKind.unavailable,
      _ => throw const FormatException('Invalid clipboard metadata'),
    };
    final bytes = map['bytes'];
    if ((bytes != null && (bytes is! int || bytes < 0)) ||
        map['internal'] is! bool) {
      throw const FormatException('Invalid clipboard metadata');
    }
    return RootClipboardMetadata(
      kind: kind,
      bytes: bytes as int?,
      internal: map['internal'] as bool,
    );
  }
}

class RootClipboardSnapshot {
  const RootClipboardSnapshot(this.metadata, this.text);
  final RootClipboardMetadata metadata;
  final String? text;
}

class RootClipboardInfo {
  const RootClipboardInfo({
    required this.session,
    required this.sdk,
    required this.uid,
    required this.userId,
    required this.api,
  });
  final int session;
  final int sdk;
  final int uid;
  final int userId;
  final String api;

  factory RootClipboardInfo.fromMap(Map<Object?, Object?> map) {
    if (map['session'] is! int ||
        (map['session'] as int) < 1 ||
        map['sdk'] is! int ||
        (map['sdk'] as int) < 24 ||
        map['uid'] is! int ||
        map['uid'] != 2000 ||
        map['userId'] is! int ||
        (map['userId'] as int) < 0 ||
        !const {
          'PACKAGE_ONLY',
          'USER',
          'ATTRIBUTION_USER',
          'ATTRIBUTION_USER_DEVICE',
        }.contains(map['api'])) {
      throw const FormatException('Unexpected bridge identity or API');
    }
    return RootClipboardInfo(
      session: map['session'] as int,
      sdk: map['sdk'] as int,
      uid: map['uid'] as int,
      userId: map['userId'] as int,
      api: map['api'] as String,
    );
  }
}

class RootClipboardEvent {
  const RootClipboardEvent({
    required this.session,
    this.metadata,
    this.errorCode,
    this.stopped = false,
  });
  final int session;
  final RootClipboardMetadata? metadata;
  final String? errorCode;
  final bool stopped;

  factory RootClipboardEvent.fromMap(Map<Object?, Object?> map) {
    final session = map['session'];
    if (session is! int || session < 0) {
      throw const FormatException('Invalid bridge session');
    }
    return switch (map['event']) {
      'clipboard' => RootClipboardEvent(
        session: session,
        metadata: RootClipboardMetadata.fromMap(
          map['snapshot'] as Map<Object?, Object?>,
        ),
      ),
      'stopped' || 'error' => RootClipboardEvent(
        session: session,
        stopped: map['event'] == 'stopped',
        errorCode: map['code'] is String
            ? map['code'] as String
            : 'bridge_failed',
      ),
      _ => throw const FormatException('Invalid bridge event'),
    };
  }
}
