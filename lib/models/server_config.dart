import 'package:uuid/uuid.dart';

/// Storage protocol used by a configured server.
enum StorageType {
  webDav,
  s3;

  String get jsonValue => switch (this) {
    StorageType.webDav => 'webdav',
    StorageType.s3 => 's3',
  };

  static StorageType fromJson(Object? value) {
    return value == 's3' ? StorageType.s3 : StorageType.webDav;
  }
}

/// Configuration model for one WebDAV or S3-compatible server.
class ServerConfig {
  final String id;
  final String name;
  final StorageType storageType;

  /// WebDAV URL or S3 endpoint URL.
  final String serverUrl;

  /// WebDAV username. Kept separate from S3 credentials for safe migration.
  final String username;

  /// WebDAV password. Kept separate from S3 credentials for safe migration.
  final String password;

  final String s3Bucket;
  final String s3Region;
  final String s3AccessKey;
  final String s3SecretKey;
  final String s3SessionToken;
  final bool s3UsePathStyle;
  final DateTime createdAt;
  final DateTime? lastUsed;
  final bool enabled;
  final String emoji;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.serverUrl,
    this.username = '',
    this.password = '',
    this.storageType = StorageType.webDav,
    this.s3Bucket = '',
    this.s3Region = 'us-east-1',
    this.s3AccessKey = '',
    this.s3SecretKey = '',
    this.s3SessionToken = '',
    this.s3UsePathStyle = true,
    required this.createdAt,
    this.lastUsed,
    this.enabled = true,
    this.emoji = '',
  });

  /// Create a new WebDAV server config with an auto-generated ID.
  factory ServerConfig.create({
    required String name,
    required String serverUrl,
    required String username,
    required String password,
    String emoji = '',
  }) {
    return ServerConfig(
      id: const Uuid().v4(),
      name: name,
      serverUrl: serverUrl,
      username: username,
      password: password,
      createdAt: DateTime.now(),
      emoji: emoji,
    );
  }

  /// Create a new S3-compatible server config with an auto-generated ID.
  factory ServerConfig.createS3({
    required String name,
    required String endpoint,
    required String bucket,
    required String region,
    required String accessKey,
    required String secretKey,
    String sessionToken = '',
    bool usePathStyle = true,
    String emoji = '',
  }) {
    return ServerConfig(
      id: const Uuid().v4(),
      name: name,
      storageType: StorageType.s3,
      serverUrl: endpoint,
      s3Bucket: bucket,
      s3Region: region,
      s3AccessKey: accessKey,
      s3SecretKey: secretKey,
      s3SessionToken: sessionToken,
      s3UsePathStyle: usePathStyle,
      createdAt: DateTime.now(),
      emoji: emoji,
    );
  }

  bool get isS3 => storageType == StorageType.s3;

  /// Check if this backend has all required connection fields.
  bool get isConfigured {
    if (isS3) {
      return serverUrl.isNotEmpty &&
          s3Bucket.isNotEmpty &&
          s3Region.isNotEmpty &&
          s3AccessKey.isNotEmpty &&
          s3SecretKey.isNotEmpty;
    }
    return serverUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
  }

  String get displayAddress => isS3 ? '$serverUrl / $s3Bucket' : serverUrl;

  /// Stable identity used when importing configurations.
  String get identityKey => isS3
      ? '${storageType.jsonValue}|$serverUrl|$s3Bucket|$s3AccessKey'
      : '${storageType.jsonValue}|$serverUrl|$username';

  ServerConfig copyWith({
    String? id,
    String? name,
    StorageType? storageType,
    String? serverUrl,
    String? username,
    String? password,
    String? s3Bucket,
    String? s3Region,
    String? s3AccessKey,
    String? s3SecretKey,
    String? s3SessionToken,
    bool? s3UsePathStyle,
    DateTime? createdAt,
    DateTime? lastUsed,
    bool? enabled,
    String? emoji,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      storageType: storageType ?? this.storageType,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      s3Bucket: s3Bucket ?? this.s3Bucket,
      s3Region: s3Region ?? this.s3Region,
      s3AccessKey: s3AccessKey ?? this.s3AccessKey,
      s3SecretKey: s3SecretKey ?? this.s3SecretKey,
      s3SessionToken: s3SessionToken ?? this.s3SessionToken,
      s3UsePathStyle: s3UsePathStyle ?? this.s3UsePathStyle,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
      enabled: enabled ?? this.enabled,
      emoji: emoji ?? this.emoji,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'storageType': storageType.jsonValue,
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      's3Bucket': s3Bucket,
      's3Region': s3Region,
      's3AccessKey': s3AccessKey,
      's3SecretKey': s3SecretKey,
      's3SessionToken': s3SessionToken,
      's3UsePathStyle': s3UsePathStyle,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed?.toIso8601String(),
      'enabled': enabled,
      'emoji': emoji,
    };
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      storageType: StorageType.fromJson(json['storageType']),
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      s3Bucket: json['s3Bucket'] as String? ?? '',
      s3Region: json['s3Region'] as String? ?? 'us-east-1',
      s3AccessKey: json['s3AccessKey'] as String? ?? '',
      s3SecretKey: json['s3SecretKey'] as String? ?? '',
      s3SessionToken: json['s3SessionToken'] as String? ?? '',
      s3UsePathStyle: json['s3UsePathStyle'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'] as String)
          : null,
      enabled: json['enabled'] as bool? ?? true,
      emoji: json['emoji'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerConfig &&
        other.id == id &&
        other.name == name &&
        other.storageType == storageType &&
        other.serverUrl == serverUrl &&
        other.username == username &&
        other.password == password &&
        other.s3Bucket == s3Bucket &&
        other.s3Region == s3Region &&
        other.s3AccessKey == s3AccessKey &&
        other.s3SecretKey == s3SecretKey &&
        other.s3SessionToken == s3SessionToken &&
        other.s3UsePathStyle == s3UsePathStyle &&
        other.createdAt == createdAt &&
        other.lastUsed == lastUsed &&
        other.enabled == enabled &&
        other.emoji == emoji;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    storageType,
    serverUrl,
    username,
    password,
    s3Bucket,
    s3Region,
    s3AccessKey,
    s3SecretKey,
    s3SessionToken,
    s3UsePathStyle,
    createdAt,
    lastUsed,
    enabled,
    emoji,
  ]);

  @override
  String toString() {
    return 'ServerConfig(id: $id, name: $name, type: ${storageType.jsonValue}, address: $displayAddress)';
  }
}
