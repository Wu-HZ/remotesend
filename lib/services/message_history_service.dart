import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/text_message.dart';

/// Service for managing message history with local file storage.
/// Messages are stored in JSON files organized by date (yyyy-MM-dd.json).
class MessageHistoryService {
  static const String _historyDirName = 'message_history';

  String? _historyPath;

  /// Generate a random local name.
  static String generateRandomName() {
    final adjectives = [
      'Swift', 'Bright', 'Calm', 'Eager', 'Fancy',
      'Gentle', 'Happy', 'Jolly', 'Kind', 'Lively',
      'Merry', 'Noble', 'Proud', 'Quick', 'Sharp',
      'Brave', 'Clever', 'Daring', 'Witty', 'Zesty',
    ];
    final nouns = [
      'Fox', 'Bear', 'Eagle', 'Wolf', 'Hawk',
      'Lion', 'Tiger', 'Panda', 'Koala', 'Otter',
      'Falcon', 'Raven', 'Phoenix', 'Dragon', 'Lynx',
      'Dolphin', 'Penguin', 'Owl', 'Deer', 'Rabbit',
    ];

    final random = Random();
    final adjective = adjectives[random.nextInt(adjectives.length)];
    final noun = nouns[random.nextInt(nouns.length)];
    final number = random.nextInt(100);

    return '$adjective$noun$number';
  }

  /// Initialize the service and create history directory.
  Future<void> initialize() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // For desktop, use app support directory
      final appDir = await getApplicationSupportDirectory();
      _historyPath = p.join(appDir.path, _historyDirName);
    } else {
      // For mobile, use app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      _historyPath = p.join(appDir.path, _historyDirName);
    }

    // Ensure directory exists
    final dir = Directory(_historyPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Get the file path for a specific date.
  String _getFilePath(String date) {
    return p.join(_historyPath!, '$date.json');
  }

  /// Get today's date string.
  String _getTodayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Load messages for a specific date.
  Future<List<TextMessage>> loadMessagesForDate(String date) async {
    if (_historyPath == null) await initialize();

    final file = File(_getFilePath(date));
    if (!await file.exists()) {
      return [];
    }

    try {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList
          .map((json) => TextMessage.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // If file is corrupted, return empty list
      return [];
    }
  }

  /// Load today's messages.
  Future<List<TextMessage>> loadTodayMessages() async {
    return loadMessagesForDate(_getTodayDate());
  }

  /// Load messages for multiple recent days.
  Future<List<TextMessage>> loadRecentMessages({int days = 7}) async {
    if (_historyPath == null) await initialize();

    final messages = <TextMessage>[];
    final now = DateTime.now();

    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dayMessages = await loadMessagesForDate(dateStr);
      messages.addAll(dayMessages);
    }

    return messages;
  }

  /// Save a message to today's file.
  Future<void> saveMessage(TextMessage message) async {
    if (_historyPath == null) await initialize();

    final date = message.formattedDate;
    final file = File(_getFilePath(date));

    List<TextMessage> messages = [];
    if (await file.exists()) {
      messages = await loadMessagesForDate(date);
    }

    // Add new message
    messages.add(message);

    // Save back to file
    final jsonList = messages.map((m) => m.toJson()).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonList),
    );
  }

  /// Save multiple messages to their respective date files.
  Future<void> saveMessages(List<TextMessage> newMessages) async {
    if (_historyPath == null) await initialize();

    // Group messages by date
    final messagesByDate = <String, List<TextMessage>>{};
    for (final message in newMessages) {
      final date = message.formattedDate;
      messagesByDate.putIfAbsent(date, () => []);
      messagesByDate[date]!.add(message);
    }

    // Save each date's messages
    for (final entry in messagesByDate.entries) {
      final date = entry.key;
      final messages = entry.value;
      final file = File(_getFilePath(date));

      List<TextMessage> existingMessages = [];
      if (await file.exists()) {
        existingMessages = await loadMessagesForDate(date);
      }

      // Add new messages (avoid duplicates by id)
      final existingIds = existingMessages.map((m) => m.id).toSet();
      for (final message in messages) {
        if (!existingIds.contains(message.id)) {
          existingMessages.add(message);
        }
      }

      // Sort by timestamp
      existingMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Save back to file
      final jsonList = existingMessages.map((m) => m.toJson()).toList();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(jsonList),
      );
    }
  }

  /// Get list of available history dates.
  Future<List<String>> getAvailableDates() async {
    if (_historyPath == null) await initialize();

    final dir = Directory(_historyPath!);
    if (!await dir.exists()) {
      return [];
    }

    final dates = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final fileName = p.basenameWithoutExtension(entity.path);
        dates.add(fileName);
      }
    }

    dates.sort();
    return dates;
  }

  /// Delete messages older than a certain number of days.
  Future<void> cleanupOldMessages({int keepDays = 30}) async {
    if (_historyPath == null) await initialize();

    final cutoffDate = DateTime.now().subtract(Duration(days: keepDays));
    final cutoffStr = '${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}';

    final dir = Directory(_historyPath!);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final fileName = p.basenameWithoutExtension(entity.path);
        if (fileName.compareTo(cutoffStr) < 0) {
          await entity.delete();
        }
      }
    }
  }

  /// Get the last message content (for detecting remote changes).
  Future<String?> getLastMessageContent() async {
    final messages = await loadTodayMessages();
    if (messages.isEmpty) {
      // Try yesterday
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      final yesterdayMessages = await loadMessagesForDate(yesterdayStr);
      if (yesterdayMessages.isEmpty) return null;
      return yesterdayMessages.last.content;
    }
    return messages.last.content;
  }
}
