import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'server_config.dart';

const _uuid = Uuid();

/// Per-device Gotify configuration.
class GotifyConfig {
  GotifyConfig({
    this.enabled = false,
    this.serverUrl = '',
    this.appToken = '',
    this.clientToken = '',
    String? deviceId,
    this.autoDownloadEnabled = false,
    this.wifiOnly = false,
    this.maxAutoDownloadBytes = 0,
    this.targetDeviceIds = const [],
    this.autoCopyTextEnabled = false,
    this.receiveTextInBackground = true,
    this.receiveFilesInBackground = false,
    int historyLookbackMinutes = 3,
  }) : deviceId = deviceId == null || deviceId.trim().isEmpty
           ? _uuid.v4()
           : deviceId.trim(),
       historyLookbackMinutes = historyLookbackMinutes.clamp(1, 5);

  final bool enabled;
  final String serverUrl;
  final String appToken;
  final String clientToken;
  final String deviceId;
  final bool autoDownloadEnabled;
  final bool wifiOnly;

  /// Zero means unlimited.
  final int maxAutoDownloadBytes;

  /// An empty list broadcasts to all other RemoteSend devices.
  final List<String> targetDeviceIds;

  /// Copy the newest newly-received text to this device's clipboard.
  final bool autoCopyTextEnabled;

  /// Process text events while this app is not in the foreground.
  final bool receiveTextInBackground;

  /// Process file events while this app is not in the foreground.
  final bool receiveFilesInBackground;

  /// Only offline events this recent are accepted after reconnecting.
  final int historyLookbackMinutes;

  Duration get historyLookback => Duration(minutes: historyLookbackMinutes);

  bool isWithinHistoryLookback(DateTime createdAt, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(historyLookback);
    return !createdAt.isBefore(cutoff);
  }

  bool get hasCredentials {
    final uri = Uri.tryParse(serverUrl.trim());
    return uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty &&
        appToken.trim().isNotEmpty &&
        clientToken.trim().isNotEmpty;
  }

  bool get isConfigured => enabled && hasCredentials;

  GotifyConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? appToken,
    String? clientToken,
    String? deviceId,
    bool? autoDownloadEnabled,
    bool? wifiOnly,
    int? maxAutoDownloadBytes,
    List<String>? targetDeviceIds,
    bool? autoCopyTextEnabled,
    bool? receiveTextInBackground,
    bool? receiveFilesInBackground,
    int? historyLookbackMinutes,
  }) {
    return GotifyConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      appToken: appToken ?? this.appToken,
      clientToken: clientToken ?? this.clientToken,
      deviceId: deviceId ?? this.deviceId,
      autoDownloadEnabled: autoDownloadEnabled ?? this.autoDownloadEnabled,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      maxAutoDownloadBytes: maxAutoDownloadBytes ?? this.maxAutoDownloadBytes,
      targetDeviceIds: targetDeviceIds ?? this.targetDeviceIds,
      autoCopyTextEnabled: autoCopyTextEnabled ?? this.autoCopyTextEnabled,
      receiveTextInBackground:
          receiveTextInBackground ?? this.receiveTextInBackground,
      receiveFilesInBackground:
          receiveFilesInBackground ?? this.receiveFilesInBackground,
      historyLookbackMinutes:
          historyLookbackMinutes ?? this.historyLookbackMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'serverUrl': serverUrl,
      'appToken': appToken,
      'clientToken': clientToken,
      'deviceId': deviceId,
      'autoDownloadEnabled': autoDownloadEnabled,
      'wifiOnly': wifiOnly,
      'maxAutoDownloadBytes': maxAutoDownloadBytes,
      'targetDeviceIds': targetDeviceIds,
      'autoCopyTextEnabled': autoCopyTextEnabled,
      'receiveTextInBackground': receiveTextInBackground,
      'receiveFilesInBackground': receiveFilesInBackground,
      'historyLookbackMinutes': historyLookbackMinutes,
    };
  }

  factory GotifyConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return GotifyConfig();

    return GotifyConfig(
      enabled: json['enabled'] as bool? ?? false,
      serverUrl: json['serverUrl'] as String? ?? '',
      appToken: json['appToken'] as String? ?? '',
      clientToken: json['clientToken'] as String? ?? '',
      deviceId: json['deviceId'] as String?,
      autoDownloadEnabled: json['autoDownloadEnabled'] as bool? ?? false,
      wifiOnly: json['wifiOnly'] as bool? ?? false,
      maxAutoDownloadBytes: json['maxAutoDownloadBytes'] as int? ?? 0,
      targetDeviceIds: (json['targetDeviceIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      autoCopyTextEnabled: json['autoCopyTextEnabled'] as bool? ?? false,
      receiveTextInBackground: json['receiveTextInBackground'] as bool? ?? true,
      receiveFilesInBackground:
          json['receiveFilesInBackground'] as bool? ?? false,
      historyLookbackMinutes:
          (json['historyLookbackMinutes'] as num?)?.toInt() ?? 3,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GotifyConfig &&
        other.enabled == enabled &&
        other.serverUrl == serverUrl &&
        other.appToken == appToken &&
        other.clientToken == clientToken &&
        other.deviceId == deviceId &&
        other.autoDownloadEnabled == autoDownloadEnabled &&
        other.wifiOnly == wifiOnly &&
        other.maxAutoDownloadBytes == maxAutoDownloadBytes &&
        _sameStrings(other.targetDeviceIds, targetDeviceIds) &&
        other.autoCopyTextEnabled == autoCopyTextEnabled &&
        other.receiveTextInBackground == receiveTextInBackground &&
        other.receiveFilesInBackground == receiveFilesInBackground &&
        other.historyLookbackMinutes == historyLookbackMinutes;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    serverUrl,
    appToken,
    clientToken,
    deviceId,
    autoDownloadEnabled,
    wifiOnly,
    maxAutoDownloadBytes,
    Object.hashAll(targetDeviceIds),
    autoCopyTextEnabled,
    receiveTextInBackground,
    receiveFilesInBackground,
    historyLookbackMinutes,
  );
}

bool shouldDeferRemoteEventInBackground(
  RemoteSendEvent event,
  GotifyConfig config, {
  required bool isForeground,
}) {
  if (isForeground) return false;
  return switch (event.type) {
    RemoteSendEvent.textChanged => !config.receiveTextInBackground,
    RemoteSendEvent.fileReady => !config.receiveFilesInBackground,
    _ => false,
  };
}

class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime lastSeen;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'lastSeen': lastSeen.toUtc().toIso8601String(),
  };

  factory RemoteDevice.fromJson(Map<String, dynamic> json) {
    return RemoteDevice(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unknown',
      platform: json['platform'] as String? ?? 'unknown',
      lastSeen:
          DateTime.tryParse(json['lastSeen'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class GotifyMessage {
  const GotifyMessage({
    required this.id,
    required this.applicationId,
    required this.title,
    required this.message,
    required this.date,
    required this.extras,
  });

  final int id;
  final int applicationId;
  final String title;
  final String message;
  final DateTime date;
  final Map<String, dynamic> extras;

  factory GotifyMessage.fromJson(Map<String, dynamic> json) {
    return GotifyMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      applicationId: (json['appid'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      date:
          DateTime.tryParse(json['date'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      extras: json['extras'] is Map
          ? Map<String, dynamic>.from(json['extras'] as Map)
          : const {},
    );
  }
}

class RemoteSendEvent {
  RemoteSendEvent({
    required this.type,
    required this.senderDeviceId,
    required this.senderName,
    this.targetDeviceIds = const [],
    this.payload = const {},
    String? eventId,
    DateTime? createdAt,
  }) : eventId = eventId ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  static const extrasKey = 'remotesend::event';
  static const protocolVersion = 1;

  static const deviceAnnounce = 'device_announce';
  static const textChanged = 'text_changed';
  static const fileReady = 'file_ready';
  static const fileReceived = 'file_received';

  static const newMessageIdPayloadKey = 'newMessageId';

  final String type;
  final String eventId;
  final String senderDeviceId;
  final String senderName;
  final List<String> targetDeviceIds;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  bool isForDevice(String deviceId) {
    return senderDeviceId != deviceId &&
        (targetDeviceIds.isEmpty || targetDeviceIds.contains(deviceId));
  }

  Map<String, dynamic> toJson() => {
    'version': protocolVersion,
    'type': type,
    'eventId': eventId,
    'senderDeviceId': senderDeviceId,
    'senderName': senderName,
    'targetDeviceIds': targetDeviceIds,
    'payload': payload,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toExtras() => {extrasKey: toJson()};

  factory RemoteSendEvent.fromJson(Map<String, dynamic> json) {
    return RemoteSendEvent(
      type: json['type'] as String? ?? '',
      eventId: json['eventId'] as String?,
      senderDeviceId: json['senderDeviceId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'Unknown',
      targetDeviceIds: (json['targetDeviceIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  static RemoteSendEvent? fromGotifyMessage(GotifyMessage message) {
    final raw = message.extras[extrasKey];
    if (raw is! Map) return null;

    try {
      final json = Map<String, dynamic>.from(raw);
      if ((json['version'] as num?)?.toInt() != protocolVersion) return null;
      final event = RemoteSendEvent.fromJson(json);
      if (event.type.isEmpty ||
          event.eventId.isEmpty ||
          event.senderDeviceId.isEmpty) {
        return null;
      }
      return event;
    } catch (_) {
      return null;
    }
  }
}

/// Stable, credential-free identifier used to match a WebDAV server between
/// devices whose local ServerConfig IDs may differ.
String webDavServerKey(ServerConfig server) {
  final uri = Uri.parse(server.serverUrl.trim());
  final normalized = uri.replace(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    path: uri.path.replaceAll(RegExp(r'/+$'), ''),
    query: null,
    fragment: null,
  );
  return sha256.convert('$normalized\n${server.username}'.codeUnits).toString();
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
