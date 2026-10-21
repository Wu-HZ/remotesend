import 'gotify_models.dart';

/// Clipboard sync is a switch over the existing Gotify text transport.
/// The encrypted platform vault stores this snapshot; regular app config does not.
class ClipboardSyncConfig {
  const ClipboardSyncConfig({
    required this.gotify,
    required this.name,
    this.enabled = false,
  });

  final GotifyConfig gotify;
  final String name;
  final bool enabled;

  bool get valid => gotify.isConfigured && name.length <= 128;

  ClipboardSyncConfig copyWith({
    bool? enabled,
    GotifyConfig? gotify,
    String? name,
  }) => ClipboardSyncConfig(
    gotify: gotify ?? this.gotify,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
  );

  /// Version 1 was the short-lived paired-key prototype. Ignore its extra
  /// secret/peer fields and migrate directly to the existing Gotify targets.
  Map<String, dynamic> toJson() => {
    'version': 2,
    'gotify': gotify.toJson(),
    'name': name,
    'enabled': enabled,
  };

  factory ClipboardSyncConfig.fromJson(Map<String, dynamic> map) {
    final version = map['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported sync settings');
    }
    return ClipboardSyncConfig(
      gotify: GotifyConfig.fromJson(
        Map<String, dynamic>.from(map['gotify'] as Map),
      ),
      name: map['name'] as String? ?? 'RemoteSend',
      enabled: map['enabled'] as bool? ?? false,
    );
  }
}

class ClipboardSyncStatus {
  const ClipboardSyncStatus({
    this.phase = 'stopped',
    this.sent = 0,
    this.received = 0,
    this.peers = 0,
    this.error,
  });
  final String phase;
  final int sent, received, peers;
  final String? error;
  bool get running => phase != 'stopped' && phase != 'error';
  Map<String, dynamic> toJson() => {
    'phase': phase,
    'sent': sent,
    'received': received,
    'peers': peers,
    if (error != null) 'error': error,
  };
  factory ClipboardSyncStatus.fromJson(Map<Object?, Object?> map) =>
      ClipboardSyncStatus(
        phase: map['phase'] as String? ?? 'stopped',
        sent: map['sent'] as int? ?? 0,
        received: map['received'] as int? ?? 0,
        peers: map['peers'] as int? ?? 0,
        error: map['error'] as String?,
      );
}
