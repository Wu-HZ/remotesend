import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/text_message.dart';
import '../services/webdav_service.dart';
import 'config_provider.dart';
import 'webdav_provider.dart';

/// Provider for the selected date in message history.
final selectedDateProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
});

/// State for the message history.
class MessageHistoryState {
  final List<TextMessage> messages;
  final List<String> availableDates;
  final bool isLoading;
  final bool isSending;
  final String? error;

  const MessageHistoryState({
    this.messages = const [],
    this.availableDates = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
  });

  MessageHistoryState copyWith({
    List<TextMessage>? messages,
    List<String>? availableDates,
    bool? isLoading,
    bool? isSending,
    String? error,
  }) {
    return MessageHistoryState(
      messages: messages ?? this.messages,
      availableDates: availableDates ?? this.availableDates,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}

/// Notifier for managing message history with WebDAV sync.
class MessageHistoryNotifier extends StateNotifier<MessageHistoryState> {
  final WebDavService _webDavService;
  final Ref _ref;

  MessageHistoryNotifier(this._webDavService, this._ref)
      : super(const MessageHistoryState());

  String _getTodayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Load messages for a specific date from WebDAV.
  Future<void> loadMessagesForDate(String date) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _webDavService.readMessagesFile(date);

      if (result.isSuccess) {
        final jsonContent = result.data ?? '[]';
        final List<dynamic> jsonList = jsonDecode(jsonContent);
        final messages = jsonList
            .map((json) => TextMessage.fromJson(json as Map<String, dynamic>))
            .toList();

        // Sort by timestamp
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        state = state.copyWith(
          messages: messages,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result.error?.userMessage ?? 'Failed to load messages',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load messages: $e',
      );
    }
  }

  /// Load available dates from WebDAV.
  Future<void> loadAvailableDates() async {
    try {
      final result = await _webDavService.listMessageDates();

      if (result.isSuccess) {
        final dates = result.data ?? [];
        // Ensure today is always in the list
        final today = _getTodayDate();
        if (!dates.contains(today)) {
          dates.insert(0, today);
        }
        state = state.copyWith(availableDates: dates);
      }
    } catch (e) {
      // Silently fail, keep existing dates
    }
  }

  /// Initialize: load today's messages and available dates.
  Future<void> initialize() async {
    final today = _getTodayDate();
    _ref.read(selectedDateProvider.notifier).state = today;

    await Future.wait([
      loadMessagesForDate(today),
      loadAvailableDates(),
    ]);
  }

  /// Refresh messages for current date.
  Future<void> refresh() async {
    final date = _ref.read(selectedDateProvider);
    await loadMessagesForDate(date);
    await loadAvailableDates();
  }

  /// Send a new message.
  Future<bool> sendMessage(String content) async {
    if (content.trim().isEmpty) return false;

    final config = _ref.read(configProvider).valueOrNull;
    final localName = config?.localName ?? 'Me';
    final today = _getTodayDate();

    state = state.copyWith(isSending: true, error: null);

    try {
      // Create local message
      final message = TextMessage.local(
        content: content.trim(),
        senderName: localName,
      );

      // Read current messages for today
      final readResult = await _webDavService.readMessagesFile(today);
      List<TextMessage> todayMessages = [];

      if (readResult.isSuccess) {
        final jsonContent = readResult.data ?? '[]';
        final List<dynamic> jsonList = jsonDecode(jsonContent);
        todayMessages = jsonList
            .map((json) => TextMessage.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      // Add new message
      todayMessages.add(message);

      // Sort by timestamp
      todayMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Write back to WebDAV
      final jsonList = todayMessages.map((m) => m.toJson()).toList();
      final jsonContent = const JsonEncoder.withIndent('  ').convert(jsonList);
      final writeResult = await _webDavService.writeMessagesFile(today, jsonContent);

      if (writeResult.isSuccess) {
        // Update state if viewing today
        final selectedDate = _ref.read(selectedDateProvider);
        if (selectedDate == today) {
          state = state.copyWith(
            messages: todayMessages,
            isSending: false,
          );
        } else {
          state = state.copyWith(isSending: false);
        }
        return true;
      } else {
        state = state.copyWith(
          isSending: false,
          error: 'Failed to sync message',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        error: 'Failed to send: $e',
      );
      return false;
    }
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Delete messages by IDs and sync to WebDAV.
  Future<bool> deleteMessages(Set<String> messageIds) async {
    if (messageIds.isEmpty) return true;

    final today = _getTodayDate();
    final selectedDate = _ref.read(selectedDateProvider);

    // Only allow deleting from today's messages
    if (selectedDate != today) return false;

    state = state.copyWith(isSending: true, error: null);

    try {
      // Read current messages
      final readResult = await _webDavService.readMessagesFile(today);
      List<TextMessage> todayMessages = [];

      if (readResult.isSuccess) {
        final jsonContent = readResult.data ?? '[]';
        final List<dynamic> jsonList = jsonDecode(jsonContent);
        todayMessages = jsonList
            .map((json) => TextMessage.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      // Filter out deleted messages
      todayMessages.removeWhere((m) => messageIds.contains(m.id));

      // Write back to WebDAV
      final jsonList = todayMessages.map((m) => m.toJson()).toList();
      final jsonContent = const JsonEncoder.withIndent('  ').convert(jsonList);
      final writeResult = await _webDavService.writeMessagesFile(today, jsonContent);

      if (writeResult.isSuccess) {
        state = state.copyWith(
          messages: todayMessages,
          isSending: false,
        );
        return true;
      } else {
        state = state.copyWith(
          isSending: false,
          error: 'Failed to sync deletions',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        error: 'Failed to delete: $e',
      );
      return false;
    }
  }
}

/// Provider for message history state management.
final messageHistoryProvider =
    StateNotifierProvider<MessageHistoryNotifier, MessageHistoryState>((ref) {
  final webDavService = ref.watch(webDavServiceProvider);
  return MessageHistoryNotifier(webDavService, ref);
});

/// Provider for local name.
final localNameProvider = Provider<String>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.localName,
    orElse: () => 'Me',
  );
});
