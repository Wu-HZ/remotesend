import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/clipboard_sync_history.dart';

class ClipboardSyncHistoryScreen extends StatefulWidget {
  const ClipboardSyncHistoryScreen({super.key});

  @override
  State<ClipboardSyncHistoryScreen> createState() =>
      _ClipboardSyncHistoryScreenState();
}

class _ClipboardSyncHistoryScreenState
    extends State<ClipboardSyncHistoryScreen> {
  final _history = const ClipboardSyncHistory();
  List<ClipboardSyncHistoryRecord> _recent = const [];
  Map<String, List<ClipboardSyncHistoryRecord>> _archives = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final recent = await _history.recent();
      final archives = await _history.archives();
      if (mounted) {
        setState(() {
          _recent = recent;
          _archives = archives;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clipboardSyncHistoryClear),
        content: Text(l10n.clipboardSyncHistoryClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.clipboardSyncHistoryClear),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _history.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.clipboardSyncHistoryTitle),
          actions: [
            IconButton(
              tooltip: l10n.clipboardSyncHistoryClear,
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.clipboardSyncHistoryRecent),
              Tab(text: l10n.clipboardSyncHistoryArchive),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10n.clipboardSyncHistoryLocalOnly),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _records(_recent, l10n.clipboardSyncHistoryEmpty),
                        _archiveList(l10n.clipboardSyncHistoryEmpty),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _archiveList(String empty) {
    if (_archives.isEmpty) return Center(child: Text(empty));
    return ListView(
      children: [
        for (final entry in _archives.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _records(entry.value, empty, nested: true),
        ],
      ],
    );
  }

  Widget _records(
    List<ClipboardSyncHistoryRecord> records,
    String empty, {
    bool nested = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (records.isEmpty) return Center(child: Text(empty));
    return ListView.builder(
      shrinkWrap: nested,
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      itemCount: records.length,
      itemBuilder: (context, index) {
        final item = records[index];
        return ListTile(
          leading: Icon(
            item.direction == 'sent' ? Icons.north_east : Icons.south_west,
          ),
          title: Text(item.text, maxLines: 4, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${item.direction == 'sent' ? l10n.clipboardSyncHistorySent : l10n.clipboardSyncHistoryReceived} · ${item.device} · ${MaterialLocalizations.of(context).formatShortDate(item.at)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(item.at))}',
          ),
          trailing: IconButton(
            tooltip: MaterialLocalizations.of(context).copyButtonLabel,
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => Clipboard.setData(ClipboardData(text: item.text)),
          ),
        );
      },
    );
  }
}
