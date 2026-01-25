import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // URL regex pattern
  static final _urlRegex = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;

    await ref.read(messageHistoryProvider.notifier).initialize();
    _scrollToBottom();
  }

  void _onTextChanged() {
    // Trigger rebuild to update send button state
    setState(() {});
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
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

  bool _isUrl(String text) {
    return _urlRegex.hasMatch(text.trim());
  }

  String? _extractUrl(String text) {
    final match = _urlRegex.firstMatch(text.trim());
    return match?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    final isConfigured = ref.watch(isConfiguredProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final historyState = ref.watch(messageHistoryProvider);
    final autoPullState = ref.watch(autoPullProvider);
    final localName = ref.watch(localNameProvider);
    final selectedDate = ref.watch(selectedDateProvider);

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
        title: GestureDetector(
          onTap: canSync ? () => _showDatePicker(historyState.availableDates) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatDateForTitle(selectedDate)),
              if (canSync) ...[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ],
          ),
        ),
        actions: [
          // Sync status indicator
          if (historyState.isSending || historyState.isLoading || autoPullState.isPolling)
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
            child: historyState.isLoading && historyState.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : historyState.messages.isEmpty
                    ? _buildEmptyState(selectedDate)
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

          // Input area (only show for today)
          if (_isToday(selectedDate))
            _buildInputArea(canSync, historyState.isSending),
        ],
      ),
    );
  }

  String _formatDateForTitle(String date) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    if (date == todayStr) {
      return 'Today';
    } else if (date == yesterdayStr) {
      return 'Yesterday';
    } else {
      return date;
    }
  }

  bool _isToday(String date) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return date == todayStr;
  }

  void _showDatePicker(List<String> availableDates) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Date',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableDates.length,
                itemBuilder: (context, index) {
                  final date = availableDates[index];
                  final selectedDate = ref.read(selectedDateProvider);
                  final isSelected = date == selectedDate;

                  return ListTile(
                    title: Text(_formatDateForTitle(date)),
                    subtitle: Text(date),
                    trailing: isSelected ? const Icon(Icons.check) : null,
                    selected: isSelected,
                    onTap: () {
                      Navigator.pop(context);
                      _selectDate(date);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectDate(String date) {
    ref.read(selectedDateProvider.notifier).state = date;
    ref.read(messageHistoryProvider.notifier).loadMessagesForDate(date);
  }

  void _toggleAutoSync() {
    final config = ref.read(configProvider).valueOrNull;
    final refreshInterval = config?.refreshIntervalSeconds ?? 3;
    ref.read(autoPullProvider.notifier).toggle(refreshInterval);
  }

  Future<void> _manualRefresh() async {
    await ref.read(messageHistoryProvider.notifier).refresh();
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

  Widget _buildEmptyState(String selectedDate) {
    final isToday = _isToday(selectedDate);

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
            isToday ? 'No messages yet' : 'No messages on this day',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          if (isToday) ...[
            const SizedBox(height: 8),
            Text(
              'Send a message to get started',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.outline.withAlpha(150),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageList(List<TextMessage> messages, String localName) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return _buildMessageBubble(messages[index], localName);
      },
    );
  }

  Widget _buildMessageBubble(TextMessage message, String localName) {
    final isLocal = message.isLocal;
    final colorScheme = Theme.of(context).colorScheme;
    final isUrl = _isUrl(message.content);
    final url = isUrl ? _extractUrl(message.content) : null;

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
              onTap: () => _copyMessage(message.content),
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
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: isLocal ? Colors.white : colorScheme.onSurface,
                      ),
                    ),
                    // URL Open button
                    if (isUrl && url != null) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _openUrl(url),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isLocal
                                ? Colors.white.withAlpha(30)
                                : colorScheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_new,
                                size: 14,
                                color: isLocal ? Colors.white : colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Open',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isLocal ? Colors.white : colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open link'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
