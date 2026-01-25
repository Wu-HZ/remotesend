import 'dart:convert';
import 'server_config.dart';
import '../services/message_history_service.dart';

/// Configuration model for app settings with multi-server support.
class AppConfig {
  static const int currentVersion = 2;

  final int version;
  final List<ServerConfig> servers;
  final String? activeServerId;
  final bool portableMode;
  final int refreshIntervalSeconds;
  final String downloadLocation;
  final String localName; // Local device name for chat display

  AppConfig({
    this.version = currentVersion,
    this.servers = const [],
    this.activeServerId,
    this.portableMode = false,
    this.refreshIntervalSeconds = 3,
    this.downloadLocation = '',
    String? localName,
  }) : localName = localName ?? MessageHistoryService.generateRandomName();

  /// Get the currently active server configuration.
  ServerConfig? get activeServer {
    if (activeServerId == null || servers.isEmpty) return null;
    try {
      return servers.firstWhere((s) => s.id == activeServerId);
    } catch (e) {
      return servers.isNotEmpty ? servers.first : null;
    }
  }

  /// Backward-compatible getter for server URL.
  String get serverUrl => activeServer?.serverUrl ?? '';

  /// Backward-compatible getter for username.
  String get username => activeServer?.username ?? '';

  /// Backward-compatible getter for password.
  String get password => activeServer?.password ?? '';

  /// Check if the configuration has valid credentials.
  bool get isConfigured => activeServer?.isConfigured ?? false;

  /// Create a copy with updated fields.
  AppConfig copyWith({
    int? version,
    List<ServerConfig>? servers,
    String? activeServerId,
    bool? portableMode,
    int? refreshIntervalSeconds,
    String? downloadLocation,
    String? localName,
  }) {
    return AppConfig(
      version: version ?? this.version,
      servers: servers ?? this.servers,
      activeServerId: activeServerId ?? this.activeServerId,
      portableMode: portableMode ?? this.portableMode,
      refreshIntervalSeconds: refreshIntervalSeconds ?? this.refreshIntervalSeconds,
      downloadLocation: downloadLocation ?? this.downloadLocation,
      localName: localName ?? this.localName,
    );
  }

  /// Create a copy with cleared active server (useful when passing null explicitly).
  AppConfig copyWithNullActiveServer({
    int? version,
    List<ServerConfig>? servers,
    bool? portableMode,
    int? refreshIntervalSeconds,
    String? downloadLocation,
    String? localName,
  }) {
    return AppConfig(
      version: version ?? this.version,
      servers: servers ?? this.servers,
      activeServerId: null,
      portableMode: portableMode ?? this.portableMode,
      refreshIntervalSeconds: refreshIntervalSeconds ?? this.refreshIntervalSeconds,
      downloadLocation: downloadLocation ?? this.downloadLocation,
      localName: localName ?? this.localName,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'servers': servers.map((s) => s.toJson()).toList(),
      'activeServerId': activeServerId,
      'portableMode': portableMode,
      'refreshIntervalSeconds': refreshIntervalSeconds,
      'downloadLocation': downloadLocation,
      'localName': localName,
    };
  }

  /// Create from JSON map.
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;

    // Handle v1 config (single server)
    if (version == 1 || !json.containsKey('servers')) {
      return AppConfig._migrateFromV1(json);
    }

    // Handle v2+ config (multi-server)
    final serversList = (json['servers'] as List<dynamic>?)
        ?.map((s) => ServerConfig.fromJson(s as Map<String, dynamic>))
        .toList() ?? [];

    return AppConfig(
      version: version,
      servers: serversList,
      activeServerId: json['activeServerId'] as String?,
      portableMode: json['portableMode'] as bool? ?? false,
      refreshIntervalSeconds: json['refreshIntervalSeconds'] as int? ?? 3,
      downloadLocation: json['downloadLocation'] as String? ?? '',
      localName: json['localName'] as String?,
    );
  }

  /// Migrate from v1 (single server) config to v2 (multi-server) config.
  factory AppConfig._migrateFromV1(Map<String, dynamic> json) {
    final serverUrl = json['serverUrl'] as String? ?? '';
    final username = json['username'] as String? ?? '';
    final password = json['password'] as String? ?? '';

    List<ServerConfig> servers = [];
    String? activeServerId;

    // Only create a server if there are actual credentials
    if (serverUrl.isNotEmpty || username.isNotEmpty) {
      // Generate a friendly name from the URL
      String name = 'My Server';
      if (serverUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(serverUrl);
          name = uri.host.isNotEmpty ? uri.host : 'My Server';
        } catch (e) {
          name = 'My Server';
        }
      }

      final server = ServerConfig.create(
        name: name,
        serverUrl: serverUrl,
        username: username,
        password: password,
      );
      servers = [server];
      activeServerId = server.id;
    }

    return AppConfig(
      version: AppConfig.currentVersion,
      servers: servers,
      activeServerId: activeServerId,
      portableMode: json['portableMode'] as bool? ?? false,
      refreshIntervalSeconds: json['refreshIntervalSeconds'] as int? ?? 3,
      downloadLocation: json['downloadLocation'] as String? ?? '',
      localName: json['localName'] as String?,
    );
  }

  /// Serialize to JSON string.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parse from JSON string.
  factory AppConfig.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return AppConfig.fromJson(json);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppConfig) return false;
    if (other.version != version ||
        other.activeServerId != activeServerId ||
        other.portableMode != portableMode ||
        other.refreshIntervalSeconds != refreshIntervalSeconds ||
        other.downloadLocation != downloadLocation ||
        other.localName != localName ||
        other.servers.length != servers.length) {
      return false;
    }
    for (int i = 0; i < servers.length; i++) {
      if (servers[i] != other.servers[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    return Object.hash(
      version,
      Object.hashAll(servers),
      activeServerId,
      portableMode,
      refreshIntervalSeconds,
      downloadLocation,
      localName,
    );
  }

  @override
  String toString() {
    return 'AppConfig(version: $version, servers: ${servers.length}, activeServerId: $activeServerId, portableMode: $portableMode)';
  }
}
