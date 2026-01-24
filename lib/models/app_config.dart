import 'dart:convert';

/// Configuration model for WebDAV connection and app settings.
class AppConfig {
  final String serverUrl;
  final String username;
  final String password;
  final bool portableMode;

  const AppConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.portableMode = false,
  });

  /// Check if the configuration has valid credentials.
  bool get isConfigured =>
      serverUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  /// Create a copy with updated fields.
  AppConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    bool? portableMode,
  }) {
    return AppConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      portableMode: portableMode ?? this.portableMode,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'portableMode': portableMode,
    };
  }

  /// Create from JSON map.
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      portableMode: json['portableMode'] as bool? ?? false,
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
    return other is AppConfig &&
        other.serverUrl == serverUrl &&
        other.username == username &&
        other.password == password &&
        other.portableMode == portableMode;
  }

  @override
  int get hashCode {
    return Object.hash(serverUrl, username, password, portableMode);
  }

  @override
  String toString() {
    return 'AppConfig(serverUrl: $serverUrl, username: $username, portableMode: $portableMode)';
  }
}
