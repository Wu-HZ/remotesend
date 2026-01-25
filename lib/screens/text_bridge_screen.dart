import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/text_message.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';
import '../providers/message_history_provider.dart';

/// Text Bridge screen with chat-like interface.
class TextBridgeScreen extends ConsumerStatefulWidget {
  const TextBridgeScreen({super.key});

  @override
  ConsumerState<TextBridgeScreen> createState() => _TextBridgeScreenState();
}

class _TextBridgeScreenState extends ConsumerState<TextBridgeScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;

    await ref.read(messageHistoryProvider.notifier).initialize();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConfigured = ref.watch(isConfiguredProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final historyState = ref.watch(messageHistoryProvider);
    final autoPullState = ref.watch(autoPullProvider);
    final localName = ref.watch(localNameProvider);

    // Listen for auto-pull updates to check for remote messages
    ref.listen<AutoPullState>(autoPullProvider, (previous, next) {
      if (previous?.lastCheckTime != next.lastCheckTime && !next.isPolling) {
        ref.read(messageHistoryProvider.notifier).checkForRemoteMessages();
      }
    });

    // Scroll to bottom when new messages arrive
    ref.listen<MessageHistoryState>(messageHistoryProvider, (previous, next) {
      if ((previous?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
    });

    final isConnected = connectionStatus.state == WebDavConnectionState.connected;
    final canSync = isConfigured && isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text Bridge'),
        actions: [
          // Sync status indicator
          if (historyState.isSending || autoPullState.isPolling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          // Auto-sync toggle
          if (canSync)
            IconButton(
              onPressed: () => _toggleAutoSync(),
              icon: Icon(
                autoPullState.isEnabled ? Icons.sync : Icons.sync_disabled,
                color: autoPullState.isEnabled
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: autoPullState.isEnabled ? 'Auto-sync ON' : 'Auto-sync OFF',
            ),
          // Manual refresh button
          if (canSync)
            IconButton(
              onPressed: historyState.isLoading ? null : _manualRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection warning banner
          if (!canSync) _buildWarningBanner(isConfigured, isConnected),

          // Chat messages
          Expanded(
            child: historyState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : historyState.messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessageList(historyState.messages, localName),
          ),

          // Error message
          if (historyState.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.withAlpha(20),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      historyState.error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => ref.read(messageHistoryProvider.notifier).clearError(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Input area
          _buildInputArea(canSync, historyState.isSending),
        ],
      ),
    );
  }

  void _toggleAutoSync() {
    final config = ref.read(configProvider).valueOrNull;
    final refreshInterval = config?.refreshIntervalSeconds ?? 3;
    ref.read(autoPullProvider.notifier).toggle(refreshInterval);
  }

  Future<void> _manualRefresh() async {
    await ref.read(messageHistoryProvider.notifier).checkForRemoteMessages();
  }

  Widget _buildWarningBanner(bool isConfigured, bool isConnected) {
    String message;
    IconData icon;

    if (!isConfigured) {
      message = 'Configure WebDAV connection in Settings to sync';
      icon = Icons.settings;
    } else if (!isConnected) {
      message = 'Not connected. Test connection in Settings';
      icon = Icons.cloud_off;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withAlpha(30),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to get started',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.outline.withAlpha(150),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<TextMessage> messages, String localName) {
    // Group messages by date
    final groupedMessages = <String, List<TextMessage>>{};
    for (final message in messages) {
      final date = message.formattedDate;
      groupedMessages.putIfAbsent(date, () => []);
      groupedMessages[date]!.add(message);
    }

    final dates = groupedMessages.keys.toList()..sort();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: dates.length,
      itemBuilder: (context, dateIndex) {
        final date = dates[dateIndex];
        final dayMessages = groupedMessages[date]!;

        return Column(
          children: [
            // Date separator
            _buildDateSeparator(date),
            // Messages for this date
            ...dayMessages.map((message) => _buildMessageBubble(message, localName)),
          ],
        );
      },
    );
  }

  Widget _buildDateSeparator(String date) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    String displayDate;
    if (date == todayStr) {
      displayDate = 'Today';
    } else if (date == yesterdayStr) {
      displayDate = 'Yesterday';
    } else {
      displayDate = date;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Theme.of(context).colorScheme.outline.withAlpha(50))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              displayDate,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: Divider(color: Theme.of(context).colorScheme.outline.withAlpha(50))),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(TextMessage message, String localName) {
    final isLocal = message.isLocal;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isLocal ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isLocal) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.secondary,
              child: const Icon(Icons.cloud, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showMessageOptions(message),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isLocal
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isLocal ? 16 : 4),
                    bottomRight: Radius.circular(isLocal ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender name (only for remote messages or if different from current local name)
                    if (!isLocal || message.senderName != localName)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          message.senderName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isLocal
                                ? Colors.white.withAlpha(200)
                                : colorScheme.primary,
                          ),
                        ),
                      ),
                    // Message content
                    SelectableText(
                      message.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: isLocal ? Colors.white : colorScheme.onSurface,
                      ),
                    ),
                    // Timestamp
                    const SizedBox(height: 4),
                    Text(
                      message.formattedTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: isLocal
                            ? Colors.white.withAlpha(150)
                            : colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isLocal) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primary,
              child: Text(
                localName.isNotEmpty ? localName[0].toUpperCase() : 'M',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showMessageOptions(TextMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.content));
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('Share - coming soon'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(bool canSync, bool isSending) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(30),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text input
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: canSync && !isSending ? (_) => _sendMessage() : null,
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          FloatingActionButton.small(
            onPressed: canSync && !isSending && _textController.text.trim().isNotEmpty
                ? _sendMessage
                : null,
            elevation: 0,
            child: isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    await ref.read(messageHistoryProvider.notifier).sendMessage(text);
    _focusNode.requestFocus();
  }
}
