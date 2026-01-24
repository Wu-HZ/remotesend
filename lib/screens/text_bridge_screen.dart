import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';

/// Text Bridge screen for sending and receiving text via WebDAV buffer.
class TextBridgeScreen extends ConsumerStatefulWidget {
  const TextBridgeScreen({super.key});

  @override
  ConsumerState<TextBridgeScreen> createState() => _TextBridgeScreenState();
}

class _TextBridgeScreenState extends ConsumerState<TextBridgeScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Sync text controller with buffer state
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Update local buffer state without syncing
    ref.read(bufferProvider.notifier).updateLocalContent(_textController.text);
  }

  @override
  Widget build(BuildContext context) {
    final isConfigured = ref.watch(isConfiguredProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final bufferState = ref.watch(bufferProvider);

    // Sync controller with buffer state when it changes externally
    if (_textController.text != bufferState.content && !_focusNode.hasFocus) {
      _textController.text = bufferState.content;
      _textController.selection = TextSelection.collapsed(
        offset: bufferState.content.length,
      );
    }

    final isConnected = connectionStatus.state == WebDavConnectionState.connected;
    final canSync = isConfigured && isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text Bridge'),
        actions: [
          // Status indicator in app bar
          if (bufferState.isLoading || bufferState.isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner
          if (!canSync) _buildWarningBanner(isConfigured, isConnected),

          // Status bar
          _buildStatusBar(bufferState),

          // Text field
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Enter text to share...',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                ),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
          ),

          // Error message
          if (bufferState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.red.withAlpha(25),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          bufferState.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Action buttons
          _buildActionButtons(canSync, bufferState),
        ],
      ),
    );
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

  Widget _buildStatusBar(BufferState bufferState) {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (bufferState.isLoading) {
      statusText = 'Pulling from server...';
      statusIcon = Icons.cloud_download;
      statusColor = Colors.blue;
    } else if (bufferState.isSaving) {
      statusText = 'Pushing to server...';
      statusIcon = Icons.cloud_upload;
      statusColor = Colors.blue;
    } else if (bufferState.lastSync != null) {
      final ago = DateTime.now().difference(bufferState.lastSync!);
      statusText = _formatSyncTime(ago);
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
    } else {
      statusText = 'Not synced yet';
      statusIcon = Icons.sync_disabled;
      statusColor = Colors.grey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            '${_textController.text.length} characters',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSyncTime(Duration ago) {
    if (ago.inSeconds < 10) {
      return 'Synced just now';
    } else if (ago.inSeconds < 60) {
      return 'Synced ${ago.inSeconds}s ago';
    } else if (ago.inMinutes < 60) {
      return 'Synced ${ago.inMinutes}m ago';
    } else {
      return 'Synced ${ago.inHours}h ago';
    }
  }

  Widget _buildActionButtons(bool canSync, BufferState bufferState) {
    final isLoading = bufferState.isLoading || bufferState.isSaving;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Primary actions row
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: canSync && !isLoading ? _pullFromRemote : null,
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Pull'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canSync && !isLoading ? _pushToRemote : null,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Push'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Secondary actions row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _textController.text.isNotEmpty ? _copyToClipboard : null,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _textController.text.isNotEmpty ? _pasteFromClipboard : null,
                  icon: const Icon(Icons.paste),
                  label: const Text('Paste'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _textController.text.isNotEmpty ? _clearText : null,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pullFromRemote() async {
    final success = await ref.read(bufferProvider.notifier).pullFromRemote();

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Text pulled from server'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Error is already shown in the UI
    }
  }

  Future<void> _pushToRemote() async {
    final success = await ref.read(bufferProvider.notifier).pushToRemote(
      _textController.text,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Text pushed to server'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Error is already shown in the UI
    }
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _textController.text));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _textController.text = data!.text!;
        _textController.selection = TextSelection.collapsed(
          offset: data.text!.length,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pasted from clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _clearText() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Text'),
        content: const Text('Are you sure you want to clear the text?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _textController.clear();
              });
              ref.read(bufferProvider.notifier).updateLocalContent('');
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
