import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_localizations.dart';
import '../providers/clipboard_sync_provider.dart';
import '../providers/gotify_provider.dart';

class ClipboardSyncScreen extends ConsumerWidget {
  const ClipboardSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(clipboardSyncProvider);
    final controller = ref.read(clipboardSyncProvider.notifier);
    final config = state.config;
    if (!state.loaded || config == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.clipboardSyncTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final devices = ref.watch(gotifyProvider).devices;
    final targets = config.gotify.targetDeviceIds;
    final targetNames = targets.map((id) => devices[id]?.name ?? id).toList();
    final busy = state.busy;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.clipboardSyncTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.clipboardSyncSimpleNotice),
              const SizedBox(height: 20),
              SwitchListTile(
                key: const ValueKey('clipboard-sync-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.clipboardSyncTitle),
                subtitle: Text(_phase(l10n, state.status.phase)),
                value: config.enabled,
                onChanged: busy
                    ? null
                    : (enabled) async {
                        if (!enabled) {
                          await controller.stop();
                          return;
                        }
                        if (Platform.isAndroid &&
                            !(await Permission.notification.request())
                                .isGranted) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.clipboardSyncNotification),
                              ),
                            );
                          }
                          return;
                        }
                        await controller.start();
                      },
              ),
              if (busy) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                l10n.clipboardSyncCounts(
                  state.status.peers,
                  state.status.sent,
                  state.status.received,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.clipboardSyncUsesGotifyTargets,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (targets.isEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices),
                  title: Text(l10n.gotifyAllDevices),
                )
              else
                for (var i = 0; i < targets.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices),
                    title: Text(targetNames[i]),
                    subtitle: Text(targets[i]),
                  ),
              if (state.error != null || state.status.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.error == 'notification_permission'
                      ? l10n.clipboardSyncNotification
                      : l10n.clipboardSyncError(
                          state.error ?? state.status.error!,
                        ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _phase(AppLocalizations l10n, String phase) => switch (phase) {
    'running' => l10n.clipboardSyncRunning,
    'waiting' => l10n.clipboardSyncWaiting,
    'connecting' => l10n.clipboardSyncConnecting,
    'reconnecting' => l10n.clipboardSyncReconnecting,
    'paused' => l10n.clipboardSyncPaused,
    'error' => l10n.clipboardSyncFailed,
    _ => l10n.clipboardSyncStopped,
  };
}
