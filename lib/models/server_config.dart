import 'package:uuid/uuid.dart';

/// Configuration model for a single WebDAV server.
class ServerConfig {
  final String id;
  final String name;
  final String serverUrl;
  final String username;
  final String password;
  final DateTime createdAt;
  final DateTime? lastUsed;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.createdAt,
    this.lastUsed,
  });

  /// Create a new server config with auto-generated ID.
  factory ServerConfig.create({
    required String name,
    required String serverUrl,
    required String username,
    required String password,
  }) {
    return ServerConfig(
      id: const Uuid().v4(),
      name: name,
      serverUrl: serverUrl,
      username: username,
      password: password,
      createdAt: DateTime.now(),
    );
  }

  /// Check if the server config has valid credentials.
  bool get isConfigured =>
      serverUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  /// Create a copy with updated fields.
  ServerConfig copyWith({
    String? id,
    String? name,
    String? serverUrl,
    String? username,
    String? password,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed?.toIso8601String(),
    };
  }

  /// Create from JSON map.
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      serverUrl: json['serverUrl'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerConfig &&
        other.id == id &&
        other.name == name &&
        other.serverUrl == serverUrl &&
        other.username == username &&
        other.password == password &&
        other.createdAt == createdAt &&
        other.lastUsed == lastUsed;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, serverUrl, username, password, createdAt, lastUsed);
  }

  @override
  String toString() {
    return 'ServerConfig(id: $id, name: $name, serverUrl: $serverUrl)';
  }
}
