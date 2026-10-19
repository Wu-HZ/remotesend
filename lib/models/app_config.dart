import 'dart:convert';
import 'dart:math';

import 'gotify_models.dart';
import 'server_config.dart';
import 'server_endpoint.dart';

/// Generate a random local name.
String _generateRandomName() {
  final adjectives = [
    'Swift',
    'Bright',
    'Calm',
    'Eager',
    'Fancy',
    'Gentle',
    'Happy',
    'Jolly',
    'Kind',
    'Lively',
    'Merry',
    'Noble',
    'Proud',
    'Quick',
    'Sharp',
    'Brave',
    'Clever',
    'Daring',
    'Witty',
    'Zesty',
  ];
  final nouns = [
    'Fox',
    'Bear',
    'Eagle',
    'Wolf',
    'Hawk',
    'Lion',
    'Tiger',
    'Panda',
    'Koala',
    'Otter',
    'Falcon',
    'Raven',
    'Phoenix',
    'Dragon',
    'Lynx',
    'Dolphin',
    'Penguin',
    'Owl',
    'Deer',
    'Rabbit',
  ];

  final random = Random();
  final adjective = adjectives[random.nextInt(adjectives.length)];
  final noun = nouns[random.nextInt(nouns.length)];
  final number = random.nextInt(100);

  return '$adjective$noun$number';
}

/// Configuration model for app settings with multi-server support.
class AppConfig {
  // Versions 4 and 5 contained the retired polling and S3 settings.
  // Version 10 adds per-device background text/file receive policies.
  // Version 11 adds the configurable startup page.
  // Version 12 adds the transfer-history auto-cleanup preference.
  // Version 13 adds the optional Gotify real-time text endpoint.
  static const int currentVersion = 13;

  static const String startPageText = 'text';
  static const String startPageFiles = 'files';

  // Default primary color (Material Blue 500)
  static const int defaultPrimaryColor = 0xFF009688;

  final int version;
  final List<ServerConfig> servers;
  final String? activeTextServerId; // Server for Text Bridge
  final String? activeFilesServerId; // Server for File Depot
  final bool portableMode;
  final String downloadLocation;
  final String localName; // Local device name for chat display
  final String themeMode; // 'system', 'light', 'dark'
  final int primaryColor; // Color value as int (e.g., 0xFF2196F3)
  final bool useDynamicColor; // Use system dynamic color (Material You)
  final String locale; // 'system', 'en', 'zh'
  final String dragMode; // 'instant' or 'pending'
  final String startPage; // 'text' or 'files'
  final bool chatOwnMessageLeft; // show own messages on left side too
  final GotifyConfig gotify;
  final bool autoClearTransferHistory;

  AppConfig({
    this.version = currentVersion,
    this.servers = const [],
    this.activeTextServerId,
    this.activeFilesServerId,
    this.portableMode = false,
    this.downloadLocation = '',
    String? localName,
    this.themeMode = 'system',
    this.primaryColor = defaultPrimaryColor,
    this.useDynamicColor = true,
    this.locale = 'system',
    this.dragMode = 'instant',
    this.startPage = startPageText,
    this.chatOwnMessageLeft = false,
    this.autoClearTransferHistory = true,
    GotifyConfig? gotify,
  }) : localName = localName ?? _generateRandomName(),
       gotify = gotify ?? GotifyConfig();

  /// Get the active server for Text Bridge.
  ServerConfig? get activeTextServer {
    if (activeTextServerId == null ||
        activeTextServerId == gotifyTextServerId ||
        servers.isEmpty) {
      return null;
    }
    try {
      return servers.firstWhere((s) => s.id == activeTextServerId);
    } catch (e) {
      return servers.isNotEmpty ? servers.first : null;
    }
  }

  /// Get the active server for File Depot.
  ServerConfig? get activeFilesServer {
    if (activeFilesServerId == null ||
        activeFilesServerId == gotifyTextServerId ||
        servers.isEmpty) {
      return null;
    }
    try {
      return servers.firstWhere((s) => s.id == activeFilesServerId);
    } catch (e) {
      return servers.isNotEmpty ? servers.first : null;
    }
  }

  /// Backward-compatible getter for active server (defaults to text server).
  ServerConfig? get activeServer => activeTextServer;

  /// Backward-compatible getter for server URL.
  String get serverUrl => activeServer?.serverUrl ?? '';

  /// Backward-compatible getter for username.
  String get username => activeServer?.username ?? '';

  /// Backward-compatible getter for password.
  String get password => activeServer?.password ?? '';

  /// Check if the configuration has valid credentials for text.
  bool get isTextConfigured => activeTextServerId == gotifyTextServerId
      ? gotify.registerAsTextServer && gotify.hasCredentials
      : activeTextServer?.isConfigured ?? false;

  /// Check if the configuration has valid credentials for files.
  bool get isFilesConfigured => activeFilesServer?.isConfigured ?? false;

  /// Check if either is configured (backward-compatible).
  bool get isConfigured =>
      isTextConfigured ||
      isFilesConfigured ||
      (gotify.registerAsTextServer && gotify.hasCredentials);

  /// Virtual endpoints never become WebDAV configs or file targets.
  AppConfig normalizeServerSelections() {
    final webDav = servers.where((s) => s.id != gotifyTextServerId).toList();
    final removeText =
        activeTextServerId == gotifyTextServerId &&
        !gotify.registerAsTextServer;
    final invalidFiles = activeFilesServerId == gotifyTextServerId;
    if (!removeText && !invalidFiles && webDav.length == servers.length) {
      return this;
    }
    final fallback = webDav.where((s) => s.enabled).firstOrNull?.id;
    return copyWithNullActiveServers(
      servers: webDav,
      clearText: removeText,
      clearFiles: invalidFiles,
    ).copyWith(activeTextServerId: removeText ? fallback : activeTextServerId);
  }

  /// Bottom-navigation index for the configured startup page.
  int get startPageIndex => startPage == startPageFiles ? 1 : 0;

  /// Create a copy with updated fields.
  AppConfig copyWith({
    int? version,
    List<ServerConfig>? servers,
    String? activeTextServerId,
    String? activeFilesServerId,
    bool? portableMode,
    String? downloadLocation,
    String? localName,
    String? themeMode,
    int? primaryColor,
    bool? useDynamicColor,
    String? locale,
    String? dragMode,
    String? startPage,
    bool? chatOwnMessageLeft,
    bool? autoClearTransferHistory,
    GotifyConfig? gotify,
  }) {
    return AppConfig(
      version: version ?? this.version,
      servers: servers ?? this.servers,
      activeTextServerId: activeTextServerId ?? this.activeTextServerId,
      activeFilesServerId: activeFilesServerId ?? this.activeFilesServerId,
      portableMode: portableMode ?? this.portableMode,
      downloadLocation: downloadLocation ?? this.downloadLocation,
      localName: localName ?? this.localName,
      themeMode: themeMode ?? this.themeMode,
      primaryColor: primaryColor ?? this.primaryColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      locale: locale ?? this.locale,
      dragMode: dragMode ?? this.dragMode,
      startPage: startPage ?? this.startPage,
      chatOwnMessageLeft: chatOwnMessageLeft ?? this.chatOwnMessageLeft,
      gotify: gotify ?? this.gotify,
      autoClearTransferHistory:
          autoClearTransferHistory ?? this.autoClearTransferHistory,
    );
  }

  /// Create a copy with cleared active servers.
  AppConfig copyWithNullActiveServers({
    int? version,
    List<ServerConfig>? servers,
    bool? portableMode,
    String? downloadLocation,
    String? localName,
    String? themeMode,
    int? primaryColor,
    bool? useDynamicColor,
    String? locale,
    String? dragMode,
    String? startPage,
    bool? chatOwnMessageLeft,
    bool? autoClearTransferHistory,
    GotifyConfig? gotify,
    bool clearText = false,
    bool clearFiles = false,
  }) {
    return AppConfig(
      version: version ?? this.version,
      servers: servers ?? this.servers,
      activeTextServerId: clearText ? null : activeTextServerId,
      activeFilesServerId: clearFiles ? null : activeFilesServerId,
      portableMode: portableMode ?? this.portableMode,
      downloadLocation: downloadLocation ?? this.downloadLocation,
      localName: localName ?? this.localName,
      themeMode: themeMode ?? this.themeMode,
      primaryColor: primaryColor ?? this.primaryColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      locale: locale ?? this.locale,
      dragMode: dragMode ?? this.dragMode,
      startPage: startPage ?? this.startPage,
      chatOwnMessageLeft: chatOwnMessageLeft ?? this.chatOwnMessageLeft,
      gotify: gotify ?? this.gotify,
      autoClearTransferHistory:
          autoClearTransferHistory ?? this.autoClearTransferHistory,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'servers': servers.map((s) => s.toJson()).toList(),
      'activeTextServerId': activeTextServerId,
      'activeFilesServerId': activeFilesServerId,
      'portableMode': portableMode,
      'downloadLocation': downloadLocation,
      'localName': localName,
      'themeMode': themeMode,
      'primaryColor': primaryColor,
      'useDynamicColor': useDynamicColor,
      'locale': locale,
      'dragMode': dragMode,
      'startPage': startPage,
      'chatOwnMessageLeft': chatOwnMessageLeft,
      'gotify': gotify.toJson(),
      'autoClearTransferHistory': autoClearTransferHistory,
    };
  }

  /// Create from JSON map.
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;

    // Handle v1 config (single server)
    if (version == 1 || !json.containsKey('servers')) {
      return AppConfig._migrateFromV1(json);
    }

    // Handle v2 config (multi-server with single activeServerId)
    if (version == 2 || json.containsKey('activeServerId')) {
      return AppConfig._migrateFromV2(json);
    }

    // Handle v3+ config (separate text/files server IDs). Retired keys are
    // intentionally ignored and the schema version is upgraded on next save.
    final serversList =
        (json['servers'] as List<dynamic>?)
            ?.map((s) => ServerConfig.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];

    return AppConfig(
      version: AppConfig.currentVersion,
      servers: serversList,
      activeTextServerId: json['activeTextServerId'] as String?,
      activeFilesServerId: json['activeFilesServerId'] as String?,
      portableMode: json['portableMode'] as bool? ?? false,
      downloadLocation: json['downloadLocation'] as String? ?? '',
      localName: json['localName'] as String?,
      themeMode: json['themeMode'] as String? ?? 'system',
      primaryColor: json['primaryColor'] as int? ?? defaultPrimaryColor,
      useDynamicColor: json['useDynamicColor'] as bool? ?? true,
      locale: json['locale'] as String? ?? 'system',
      dragMode: json['dragMode'] as String? ?? 'instant',
      startPage: json['startPage'] == startPageFiles
          ? startPageFiles
          : startPageText,
      chatOwnMessageLeft: json['chatOwnMessageLeft'] as bool? ?? false,
      autoClearTransferHistory:
          json['autoClearTransferHistory'] as bool? ?? true,
      gotify: GotifyConfig.fromJson(
        json['gotify'] is Map
            ? Map<String, dynamic>.from(json['gotify'] as Map)
            : null,
      ),
    ).normalizeServerSelections();
  }

  /// Migrate from v1 (single server) config.
  factory AppConfig._migrateFromV1(Map<String, dynamic> json) {
    final serverUrl = json['serverUrl'] as String? ?? '';
    final username = json['username'] as String? ?? '';
    final password = json['password'] as String? ?? '';

    List<ServerConfig> servers = [];
    String? activeServerId;

    // Only create a server if there are actual credentials
    if (serverUrl.isNotEmpty || username.isNotEmpty) {
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
      activeTextServerId: activeServerId,
      activeFilesServerId: activeServerId,
      portableMode: json['portableMode'] as bool? ?? false,
      downloadLocation: json['downloadLocation'] as String? ?? '',
      localName: json['localName'] as String?,
      themeMode: json['themeMode'] as String? ?? 'system',
      primaryColor: json['primaryColor'] as int? ?? defaultPrimaryColor,
      useDynamicColor: json['useDynamicColor'] as bool? ?? true,
      locale: json['locale'] as String? ?? 'system',
      dragMode: json['dragMode'] as String? ?? 'instant',
      chatOwnMessageLeft: json['chatOwnMessageLeft'] as bool? ?? false,
    );
  }

  /// Migrate from v2 (single activeServerId) to v3 (separate text/files IDs).
  factory AppConfig._migrateFromV2(Map<String, dynamic> json) {
    final serversList =
        (json['servers'] as List<dynamic>?)
            ?.map((s) => ServerConfig.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];

    final activeServerId = json['activeServerId'] as String?;

    return AppConfig(
      version: AppConfig.currentVersion,
      servers: serversList,
      activeTextServerId: activeServerId,
      activeFilesServerId: activeServerId,
      portableMode: json['portableMode'] as bool? ?? false,
      downloadLocation: json['downloadLocation'] as String? ?? '',
      localName: json['localName'] as String?,
      themeMode: json['themeMode'] as String? ?? 'system',
      primaryColor: json['primaryColor'] as int? ?? defaultPrimaryColor,
      useDynamicColor: json['useDynamicColor'] as bool? ?? true,
      locale: json['locale'] as String? ?? 'system',
      dragMode: json['dragMode'] as String? ?? 'instant',
      chatOwnMessageLeft: json['chatOwnMessageLeft'] as bool? ?? false,
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
        other.activeTextServerId != activeTextServerId ||
        other.activeFilesServerId != activeFilesServerId ||
        other.portableMode != portableMode ||
        other.downloadLocation != downloadLocation ||
        other.localName != localName ||
        other.themeMode != themeMode ||
        other.primaryColor != primaryColor ||
        other.useDynamicColor != useDynamicColor ||
        other.locale != locale ||
        other.dragMode != dragMode ||
        other.startPage != startPage ||
        other.chatOwnMessageLeft != chatOwnMessageLeft ||
        other.autoClearTransferHistory != autoClearTransferHistory ||
        other.gotify != gotify ||
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
      activeTextServerId,
      activeFilesServerId,
      portableMode,
      downloadLocation,
      localName,
      themeMode,
      primaryColor,
      useDynamicColor,
      locale,
      dragMode,
      startPage,
      chatOwnMessageLeft,
      gotify,
      autoClearTransferHistory,
    );
  }

  @override
  String toString() {
    return 'AppConfig(version: $version, servers: ${servers.length}, textServer: $activeTextServerId, filesServer: $activeFilesServerId)';
  }
}
