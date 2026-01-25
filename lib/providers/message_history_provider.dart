import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/text_message.dart';
import '../services/message_history_service.dart';
import '../services/webdav_service.dart';
import 'config_provider.dart';
import 'webdav_provider.dart';

/// Provider for the MessageHistoryService singleton.
final messageHistoryServiceProvider = Provider<MessageHistoryService>((ref) {
  return MessageHistoryService();
});

/// State for the message history.
class MessageHistoryState {
  final List<TextMessage> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final String? lastRemoteContent;

  const MessageHistoryState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.lastRemoteContent,
  });

  MessageHistoryState copyWith({
    List<TextMessage>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    String? lastRemoteContent,
  }) {
    return MessageHistoryState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
      lastRemoteContent: lastRemoteContent ?? this.lastRemoteContent,
    );
  }
}

/// Notifier for managing message history.
class MessageHistoryNotifier extends StateNotifier<MessageHistoryState> {
  final MessageHistoryService _historyService;
  final WebDavService _webDavService;
  final Ref _ref;

  MessageHistoryNotifier(this._historyService, this._webDavService, this._ref)
      : super(const MessageHistoryState());

  /// Initialize and load recent messages.
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _historyService.initialize();
      final messages = await _historyService.loadRecentMessages(days: 7);

      // Get last remote content for change detection
      String? lastRemote;
      if (messages.isNotEmpty) {
        final lastRemoteMsg = messages.lastWhere(
          (m) => !m.isLocal,
          orElse: () => messages.last,
        );
        lastRemote = lastRemoteMsg.content;
      }

      state = MessageHistoryState(
        messages: messages,
        lastRemoteContent: lastRemote,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load messages: $e',
      );
    }
  }

  /// Send a new message (local).
  Future<bool> sendMessage(String content) async {
    if (content.trim().isEmpty) return false;

    final config = _ref.read(configProvider).valueOrNull;
    final localName = config?.localName ?? 'Me';

    state = state.copyWith(isSending: true, error: null);

    try {
      // Create local message
      final message = TextMessage.local(
        content: content.trim(),
        senderName: localName,
      );

      // Save to local history
      await _historyService.saveMessage(message);

      // Add to current state
      final updatedMessages = [...state.messages, message];
      state = state.copyWith(
        messages: updatedMessages,
        isSending: false,
        lastRemoteContent: content.trim(),
      );

      // Push to WebDAV server
      final result = await _webDavService.writeBuffer(content.trim());
      if (!result.isSuccess) {
        state = state.copyWith(error: 'Sent locally, but failed to sync to server');
      }

      return true;
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        error: 'Failed to send: $e',
      );
      return false;
    }
  }

  /// Check for new remote messages.
  Future<void> checkForRemoteMessages() async {
    try {
      final result = await _webDavService.readBuffer();
      if (!result.isSuccess || result.data == null) return;

      final remoteContent = result.data!.trim();
      if (remoteContent.isEmpty) return;

      // Check if this is new content
      if (remoteContent != state.lastRemoteContent) {
        // Check if this content already exists in recent messages
        final exists = state.messages.any((m) => m.content == remoteContent);
        if (!exists) {
          // Create remote message
          final message = TextMessage.remote(content: remoteContent);

          // Save to local history
          await _historyService.saveMessage(message);

          // Add to current state
          final updatedMessages = [...state.messages, message];
          state = state.copyWith(
            messages: updatedMessages,
            lastRemoteContent: remoteContent,
          );
        } else {
          // Update last remote content even if message exists
          state = state.copyWith(lastRemoteContent: remoteContent);
        }
      }
    } catch (e) {
      // Silently fail for background checks
    }
  }

  /// Refresh messages from local storage.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final messages = await _historyService.loadRecentMessages(days: 7);
      state = state.copyWith(
        messages: messages,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to refresh: $e',
      );
    }
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Provider for message history state management.
final messageHistoryProvider =
    StateNotifierProvider<MessageHistoryNotifier, MessageHistoryState>((ref) {
  final historyService = ref.watch(messageHistoryServiceProvider);
  final webDavService = ref.watch(webDavServiceProvider);
  return MessageHistoryNotifier(historyService, webDavService, ref);
});

/// Provider for local name.
final localNameProvider = Provider<String>((ref) {
  final configAsync = ref.watch(configProvider);
  return configAsync.maybeWhen(
    data: (config) => config.localName,
    orElse: () => 'Me',
  );
});
