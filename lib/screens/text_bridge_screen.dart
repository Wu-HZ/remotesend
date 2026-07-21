import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
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
  final Set<String> _pendingDeletions = {};

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

    final status = ref.read(textConnectionStatusProvider);
    if (status.state != WebDavConnectionState.connected) {
      _initialized = false;
      return;
    }

    await ref.read(messageHistoryProvider.notifier).initialize();
    _scrollToBottom();
  }

  void _onTextChanged() {
    // Trigger rebuild to update send button state
    setState(() {});
  }

  @override
  void dispose() {
    ref.read(autoPullProvider.notifier).disable();
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
    final isConfigured = ref.watch(isTextConfiguredProvider);
    final connectionStatus = ref.watch(textConnectionStatusProvider);
    final historyState = ref.watch(messageHistoryProvider);
    final autoPullState = ref.watch(autoPullProvider);
    final localName = ref.watch(localNameProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final activeServer = ref.watch(activeTextServerProvider);
    final servers = ref.watch(serversListProvider);
    final l10n = AppLocalizations.of(context)!;

    // Scroll to bottom when new messages arrive
    ref.listen<MessageHistoryState>(messageHistoryProvider, (previous, next) {
      if ((previous?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
    });

    // Trigger message load once connection is ready
    if (!_initialized && connectionStatus.state == WebDavConnectionState.connected) {
      Future.microtask(_initialize);
    }

    final isConnected = connectionStatus.state == WebDavConnectionState.connected;
    final canSync = isConfigured && isConnected;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: GestureDetector(
          onTap: canSync ? () => _showDatePicker(historyState.availableDates, l10n) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatDateForTitle(selectedDate, l10n)),
              if (canSync) ...[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ],
          ),
        ),
        actions: [
          // Server selector
          if (servers.isNotEmpty)
            _buildServerSelector(activeServer, servers, l10n),
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
              tooltip: autoPullState.isEnabled ? l10n.autoSyncOn : l10n.autoSyncOff,
            ),
          // Manual refresh button
          if (canSync)
            IconButton(
              onPressed: historyState.isLoading ? null : _manualRefresh,
              icon: historyState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: l10n.refresh,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              // Connection warning banner
              if (!canSync) _buildWarningBanner(isConfigured, isConnected, l10n),

          // Chat messages
          Expanded(
            child: historyState.isLoading && historyState.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : historyState.messages.isEmpty
                    ? _buildEmptyState(selectedDate, l10n)
                    : _buildMessageList(historyState.messages, localName, l10n),
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
            _buildInputArea(canSync, historyState.isSending, l10n),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateForTitle(String date, AppLocalizations l10n) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    if (date == todayStr) {
      return l10n.today;
    } else if (date == yesterdayStr) {
      return l10n.yesterday;
    } else {
      return date;
    }
  }

  bool _isToday(String date) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return date == todayStr;
  }

  void _showDatePicker(List<String> availableDates, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.selectDate,
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
                    title: Text(_formatDateForTitle(date, l10n)),
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
    // Clear pending deletions on refresh (undo)
    setState(() {
      _pendingDeletions.clear();
    });
    try {
      ref.read(autoPullProvider.notifier).pause();
      await ref.read(messageHistoryProvider.notifier).refresh();
    } finally {
      ref.read(autoPullProvider.notifier).resume();
    }
  }

  Widget _buildServerSelector(ServerConfig? activeServer, List<ServerConfig> servers, AppLocalizations l10n) {
    return PopupMenuButton<String>(
      tooltip: l10n.switchServer,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud,
            size: 18,
            color: activeServer != null ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
      onSelected: (serverId) {
        ref.read(configProvider.notifier).switchTextServer(serverId);
        ref.read(textConnectionStatusProvider.notifier).testConnection();
        ref.read(messageHistoryProvider.notifier).refresh();
      },
      itemBuilder: (context) => servers.map((server) {
        final isActive = server.id == activeServer?.id;
        return PopupMenuItem<String>(
          value: server.id,
          child: Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      server.serverUrl,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWarningBanner(bool isConfigured, bool isConnected, AppLocalizations l10n) {
    String message;
    IconData icon;

    if (!isConfigured) {
      message = l10n.configureWebDavToSync;
      icon = Icons.settings;
    } else if (!isConnected) {
      message = l10n.notConnectedTestInSettings;
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

  Widget _buildEmptyState(String selectedDate, AppLocalizations l10n) {
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
            isToday ? l10n.noMessagesYet : l10n.noMessagesOnThisDay,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          if (isToday) ...[
            const SizedBox(height: 8),
            Text(
              l10n.sendMessageToGetStarted,
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

  Widget _buildMessageList(List<TextMessage> messages, String localName, AppLocalizations l10n) {
    // Filter out pending deletions
    final visibleMessages = messages
        .where((m) => !_pendingDeletions.contains(m.id))
        .toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: visibleMessages.length,
      itemBuilder: (context, index) {
        return _buildMessageBubble(visibleMessages[index], localName, l10n);
      },
    );
  }

  Widget _buildMessageBubble(TextMessage message, String localName, AppLocalizations l10n) {
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
              onTap: () => _copyMessage(message.content, l10n),
              onLongPress: () => _markForDeletion(message, l10n),
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
                        onTap: () => _openUrl(url, l10n),
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
                                l10n.open,
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

  void _copyMessage(String content, AppLocalizations l10n) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.copiedToClipboard),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _markForDeletion(TextMessage message, AppLocalizations l10n) {
    setState(() {
      _pendingDeletions.add(message.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.messageMarkedForDeletion),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            setState(() {
              _pendingDeletions.remove(message.id);
            });
          },
        ),
      ),
    );
  }

  Future<void> _openUrl(String url, AppLocalizations l10n) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.couldNotOpenLink),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorOpeningLink(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildInputArea(bool canSync, bool isSending, AppLocalizations l10n) {
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Text input
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: l10n.typeAMessage,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: canSync && !isSending && _textController.text.trim().isNotEmpty
                  ? (_) => _sendMessage()
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          // Paste button
          IconButton(
            onPressed: canSync && !isSending ? _sendClipboard : null,
            icon: const Icon(Icons.content_paste),
            tooltip: '发送剪贴板内容',
          ),
          const SizedBox(width: 4),
          // Send button
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: canSync &&
                      !isSending &&
                      (_textController.text.trim().isNotEmpty ||
                          _pendingDeletions.isNotEmpty)
                  ? _sendMessage
                  : null,
              icon: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final hasPendingDeletions = _pendingDeletions.isNotEmpty;

    if (text.isEmpty && !hasPendingDeletions) return;

    _textController.clear();

    try {
      ref.read(autoPullProvider.notifier).pause();

      // First, sync pending deletions
      if (hasPendingDeletions) {
        final deleteSuccess = await ref.read(messageHistoryProvider.notifier).deleteMessages(_pendingDeletions);
        if (deleteSuccess) {
          setState(() {
            _pendingDeletions.clear();
          });
        }
      }

      // Then, send new message if any
      if (text.isNotEmpty) {
        await ref.read(messageHistoryProvider.notifier).sendMessage(text);
      }
    } finally {
      ref.read(autoPullProvider.notifier).resume();
    }

    _focusNode.requestFocus();
  }

  Future<void> _sendClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;

    try {
      ref.read(autoPullProvider.notifier).pause();
      await ref.read(messageHistoryProvider.notifier).sendMessage(text);
    } finally {
      ref.read(autoPullProvider.notifier).resume();
    }
  }
}
