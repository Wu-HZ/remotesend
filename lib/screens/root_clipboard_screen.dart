import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/root_clipboard.dart';
import '../providers/root_clipboard_provider.dart';

class RootClipboardScreen extends ConsumerWidget {
  const RootClipboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final supported = ref.watch(rootClipboardSupportedProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.rootClipboardTitle)),
      body: !supported
          ? Center(child: Text(l10n.rootClipboardUnsupported))
          : const _Diagnostics(),
    );
  }
}

class _Diagnostics extends ConsumerWidget {
  const _Diagnostics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(rootClipboardDiagnosticsProvider);
    final controller = ref.read(rootClipboardDiagnosticsProvider.notifier);
    final info = state.info;
    final metadata = state.last;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.rootClipboardNotice),
            const SizedBox(height: 16),
            Text(l10n.rootClipboardSteps),
            const SizedBox(height: 24),
            Text(
              state.connected
                  ? l10n.rootClipboardActive
                  : state.busy
                  ? l10n.rootClipboardStarting
                  : l10n.rootClipboardIdle,
              key: const ValueKey('root-clipboard-status'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (state.busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const ValueKey('root-clipboard-start'),
                  onPressed: state.busy || state.connected
                      ? null
                      : controller.start,
                  icon: const Icon(Icons.security),
                  label: Text(l10n.rootClipboardStart),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('root-clipboard-stop'),
                  onPressed: state.connected || state.busy
                      ? controller.stop
                      : null,
                  icon: const Icon(Icons.stop),
                  label: Text(l10n.rootClipboardStop),
                ),
              ],
            ),
            if (info != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                l10n.rootClipboardEnvironment(
                  info.sdk,
                  info.uid,
                  info.userId,
                  info.api,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(l10n.rootClipboardChanges(state.changes)),
            if (metadata != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.rootClipboardMetadata(
                  _kind(l10n, metadata.kind),
                  metadata.bytes?.toString() ?? '—',
                  metadata.internal
                      ? l10n.rootClipboardOriginBridge
                      : l10n.rootClipboardOriginOther,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  key: const ValueKey('root-clipboard-read'),
                  onPressed: state.connected && !state.busy
                      ? controller.read
                      : null,
                  child: Text(l10n.rootClipboardRead),
                ),
                OutlinedButton(
                  key: const ValueKey('root-clipboard-probe'),
                  onPressed: state.connected && !state.busy
                      ? () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(l10n.rootClipboardProbe),
                              content: Text(l10n.rootClipboardProbeConfirm),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(l10n.cancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(l10n.confirm),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            await controller.writeProbe();
                          }
                        }
                      : null,
                  child: Text(l10n.rootClipboardProbe),
                ),
              ],
            ),
            if (state.probeMatched != null) ...[
              const SizedBox(height: 16),
              Text(
                state.probeMatched!
                    ? l10n.rootClipboardProbePassed
                    : l10n.rootClipboardProbeFailed,
                style: TextStyle(
                  color: state.probeMatched! ? colors.primary : colors.error,
                ),
              ),
            ],
            if (state.errorCode != null) ...[
              const SizedBox(height: 16),
              Text(
                l10n.rootClipboardError(state.errorCode!),
                style: TextStyle(color: colors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _kind(AppLocalizations l10n, RootClipboardKind kind) => switch (kind) {
    RootClipboardKind.text => l10n.rootClipboardKindText,
    RootClipboardKind.empty => l10n.rootClipboardKindEmpty,
    RootClipboardKind.nonText => l10n.rootClipboardKindOther,
    RootClipboardKind.sensitive => l10n.rootClipboardKindSensitive,
    RootClipboardKind.tooLarge => l10n.rootClipboardKindLarge,
    RootClipboardKind.unavailable => l10n.rootClipboardKindUnavailable,
  };
}
