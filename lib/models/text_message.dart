import 'package:uuid/uuid.dart';

/// A text message in the chat history.
class TextMessage {
  final String id;
  final String content;
  final String senderName;
  final bool isLocal;
  final DateTime timestamp;

  const TextMessage({
    required this.id,
    required this.content,
    required this.senderName,
    required this.isLocal,
    required this.timestamp,
  });

  /// Create a new local message.
  factory TextMessage.local({
    required String content,
    required String senderName,
  }) {
    return TextMessage(
      id: const Uuid().v4(),
      content: content,
      senderName: senderName,
      isLocal: true,
      timestamp: DateTime.now(),
    );
  }

  /// Create a new remote message.
  factory TextMessage.remote({
    required String content,
    String? id,
  }) {
    return TextMessage(
      id: id ?? const Uuid().v4(),
      content: content,
      senderName: 'Remote',
      isLocal: false,
      timestamp: DateTime.now(),
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'senderName': senderName,
      'isLocal': isLocal,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from JSON map.
  factory TextMessage.fromJson(Map<String, dynamic> json) {
    return TextMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      senderName: json['senderName'] as String,
      isLocal: json['isLocal'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Get formatted time string (HH:mm).
  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  /// Get formatted date string (yyyy-MM-dd).
  String get formattedDate {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'TextMessage(id: $id, sender: $senderName, isLocal: $isLocal)';
  }
}
