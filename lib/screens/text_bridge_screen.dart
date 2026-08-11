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
import '../widgets/storage_usage_widget.dart';

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
  final Set<String> _expandedMessages = {};
  final Set<String> _deletingMessages = {};

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

  void _scrollToBottomIfNearEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 100) {
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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

  List<String> _extractUrls(String text) {
    return _urlRegex
        .allMatches(text.trim())
        .map((m) => m.group(0)!)
        .toList();
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
    final servers = ref.watch(enabledServersProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen<MessageHistoryState>(messageHistoryProvider, (previous, next) {
      if ((previous?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottomIfNearEnd();
      }
    });

    if (!_initialized && connectionStatus.state == WebDavConnectionState.connected) {
      Future.microtask(_initialize);
    }

    final isConnected = connectionStatus.state == WebDavConnectionState.connected;
    final canSync = isConfigured && isConnected;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            if (canSync) StorageUsageWidget(
              provider: textStorageUsageProvider,
              clearDescription:
                  '${activeServer?.name ?? ''}上的所有文本',
              onClear: () async {
                final service = ref.read(webDavTextServiceProvider);
                final result = await service.clearAllMessages();
                if (result.isSuccess) {
                  ref.read(messageHistoryProvider.notifier).refresh();
                }
                return result.isSuccess;
              },
            ),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canSync
                    ? () => _showDatePicker(historyState.availableDates, l10n)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              ),
            ),
            const Spacer(),
          ],
        ),
        actions: [
          if (servers.isNotEmpty)
            _buildServerSelector(activeServer, servers, l10n),
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
              if (!canSync) _buildWarningBanner(isConfigured, isConnected, l10n),

          Expanded(
            child: historyState.isLoading && historyState.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : historyState.messages.isEmpty
                    ? _buildEmptyState(selectedDate, l10n)
                    : _buildMessageList(historyState.messages, localName, l10n),
          ),

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
                      style: const TextStyle(color: Colors.red, fontSize: 14),
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
          if (activeServer != null && activeServer!.emoji.isNotEmpty)
            Text(activeServer!.emoji, style: const TextStyle(fontSize: 16))
          else
            Icon(
              Icons.cloud,
              size: 18,
              color: activeServer != null ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
      onSelected: (serverId) async {
        ref.read(configProvider.notifier).switchTextServer(serverId);
        await ref.read(textConnectionStatusProvider.notifier).testConnection();
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
              SizedBox(
                width: 24,
                child: server.emoji.isNotEmpty
                    ? Text(server.emoji,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16))
                    : Icon(Icons.cloud,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  server.name,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
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
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _buildMessageBubble(message, localName, l10n,
            key: ValueKey(message.id));
      },
    );
  }

  Widget _buildMessageBubble(TextMessage message, String localName, AppLocalizations l10n, {Key? key}) {
    final isLocal = message.isLocal;
    final colorScheme = Theme.of(context).colorScheme;
    final urls = _extractUrls(message.content);
    final isDeleting = _deletingMessages.contains(message.id);
    final isExpanded = _expandedMessages.contains(message.id);
    final needsExpand = message.content.split('\n').length > 6 || message.content.length > 300;

    final displayContent = (needsExpand && !isExpanded)
        ? _truncateContent(message.content)
        : message.content;

    final textColor = isLocal ? Colors.white : colorScheme.onSurface;
    final timeColor = isLocal
        ? Colors.white.withAlpha(150)
        : colorScheme.outline;
    final linkColor = isLocal
        ? Colors.white.withAlpha(230)
        : colorScheme.primary;
    final senderName = message.senderName.trim();
    final senderInitial = senderName.isNotEmpty ? senderName[0].toUpperCase() : '?';

    // Measure if time fits on the same line as the text
    final bubbleMaxWidth = MediaQuery.of(context).size.width * 0.75 - 24; // padding
    final painter = TextPainter(
      text: TextSpan(text: displayContent, style: const TextStyle(fontSize: 14)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final timeInline = painter.width + 40 <= bubbleMaxWidth;

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: isDeleting ? 0.4 : 1.0,
        child: Row(
          mainAxisAlignment: isLocal ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isLocal) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.secondary,
                child: Text(
                  senderInitial,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!needsExpand || isExpanded)
                        timeInline && !displayContent.contains('\n')
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Flexible(
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(fontSize: 14, color: textColor),
                                        children: urls.isNotEmpty
                                            ? _buildInlineSpans(
                                                displayContent,
                                                urls,
                                                textColor,
                                                linkColor,
                                                l10n,
                                                isLocal: isLocal,
                                                colorScheme: colorScheme,
                                              )
                                            : [TextSpan(text: displayContent)],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    message.formattedTime,
                                    style: TextStyle(fontSize: 10, color: timeColor),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      style: TextStyle(fontSize: 14, color: textColor),
                                      children: urls.isNotEmpty
                                          ? _buildInlineSpans(
                                              displayContent,
                                              urls,
                                              textColor,
                                              linkColor,
                                              l10n,
                                              isLocal: isLocal,
                                              colorScheme: colorScheme,
                                            )
                                          : [TextSpan(text: displayContent)],
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      message.formattedTime,
                                      style: TextStyle(fontSize: 10, color: timeColor),
                                    ),
                                  ),
                                ],
                              )
                      else
                        Text(
                          displayContent,
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      if (needsExpand && !isExpanded)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: GestureDetector(
                            onTap: () => setState(() => _expandedMessages.add(message.id)),
                            child: Row(
                              children: [
                                Text(
                                  '展开 ↓',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: linkColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  message.formattedTime,
                                  style: TextStyle(fontSize: 10, color: timeColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (needsExpand && isExpanded)
                        GestureDetector(
                          onTap: () => setState(() => _expandedMessages.remove(message.id)),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '收起 ↑',
                              style: TextStyle(
                                fontSize: 12,
                                color: linkColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                  localName.trim().isNotEmpty
                      ? localName.trim()[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _truncateContent(String content) {
    final lines = content.split('\n');
    if (lines.length > 6) {
      return '${lines.take(6).join('\n')}...';
    }
    if (content.length > 300) {
      return '${content.substring(0, 300)}...';
    }
    return content;
  }

  List<InlineSpan> _buildInlineSpans(
    String content,
    List<String> urls,
    Color textColor,
    Color linkColor,
    AppLocalizations l10n, {
    required bool isLocal,
    required ColorScheme colorScheme,
  }) {
    final spans = <InlineSpan>[];
    int searchStart = 0;

    for (final url in urls) {
      final urlIndex = content.indexOf(url, searchStart);
      if (urlIndex == -1) continue;

      // Text before this URL
      if (urlIndex > searchStart) {
        spans.add(TextSpan(
          text: content.substring(searchStart, urlIndex),
          style: TextStyle(color: textColor),
        ));
      }

      // URL text
      spans.add(TextSpan(
        text: url,
        style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
      ));

      // Open button
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TextButton(
            onPressed: () => _openUrl(url, l10n),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: isLocal
                  ? Colors.white.withAlpha(30)
                  : colorScheme.primary.withAlpha(20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              '打开',
              style: TextStyle(
                color: linkColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ));

      searchStart = urlIndex + url.length;
    }

    // Remaining text after last URL
    if (searchStart < content.length) {
      spans.add(TextSpan(
        text: content.substring(searchStart),
        style: TextStyle(color: textColor),
      ));
    }

    return spans;
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
    setState(() => _deletingMessages.add(message.id));

    final cachedContent = message.content;

    ref.read(messageHistoryProvider.notifier).deleteMessages({message.id}).then((success) {
      if (mounted && success) {
        setState(() => _deletingMessages.remove(message.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.messageMarkedForDeletion),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: l10n.undo,
              onPressed: () {
                ref.read(messageHistoryProvider.notifier).sendMessage(cachedContent);
              },
            ),
          ),
        );
      } else if (mounted) {
        setState(() => _deletingMessages.remove(message.id));
      }
    });
  }

  Future<void> _openUrl(String url, AppLocalizations l10n) async {
    final fixed = url.startsWith('http://') || url.startsWith('https://')
        ? url
        : 'https://$url';
    final uri = Uri.parse(fixed);
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
          IconButton(
            onPressed: canSync && !isSending ? _sendClipboard : null,
            icon: const Icon(Icons.content_paste),
            tooltip: l10n.sendClipboardContent,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: canSync &&
                      !isSending &&
                      _textController.text.trim().isNotEmpty
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
    if (text.isEmpty) return;

    _textController.clear();

    try {
      ref.read(autoPullProvider.notifier).pause();
      await ref.read(messageHistoryProvider.notifier).sendMessage(text);
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
