import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class _VersionEntry {
  final String version;
  final String date;
  final List<String> changes;
  const _VersionEntry(this.version, this.date, this.changes);
}

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  List<_VersionEntry> _buildEntries(AppLocalizations l10n) {
    return [
      _VersionEntry('1.1.0', '2026-08-12', [
        l10n.changelog_1_1_0_1,
        l10n.changelog_1_1_0_2,
        l10n.changelog_1_1_0_3,
        l10n.changelog_1_1_0_4,
        l10n.changelog_1_1_0_5,
        l10n.changelog_1_1_0_6,
        l10n.changelog_1_1_0_7,
        l10n.changelog_1_1_0_8,
        l10n.changelog_1_1_0_9,
        l10n.changelog_1_1_0_10,
        l10n.changelog_1_1_0_11,
        l10n.changelog_1_1_0_12,
        l10n.changelog_1_1_0_13,
        l10n.changelog_1_1_0_14,
        l10n.changelog_1_1_0_15,
        l10n.changelog_1_1_0_16,
        l10n.changelog_1_1_0_17,
        l10n.changelog_1_1_0_18,
      ]),
      _VersionEntry('1.0.0', '2026-01-26', [
        l10n.changelog_1_0_0_1,
        l10n.changelog_1_0_0_2,
        l10n.changelog_1_0_0_3,
        l10n.changelog_1_0_0_4,
        l10n.changelog_1_0_0_5,
        l10n.changelog_1_0_0_6,
        l10n.changelog_1_0_0_7,
        l10n.changelog_1_0_0_8,
        l10n.changelog_1_0_0_9,
        l10n.changelog_1_0_0_10,
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entries = _buildEntries(l10n);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.changelog),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('v${entry.version}',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(entry.date,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...entry.changes.map((change) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: TextStyle(color: theme.colorScheme.primary)),
                            Expanded(child: Text(change)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
