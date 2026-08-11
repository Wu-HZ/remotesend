import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/webdav_provider.dart';
import 'countdown_dialog.dart';

/// A compact widget showing WebDAV storage usage, shared by Text Bridge
/// and File Depot. Tap to refresh. Includes a delete button to clear
/// all files or messages on the current server.
class StorageUsageWidget extends ConsumerWidget {
  final StateNotifierProvider<StorageUsageNotifier, StorageUsageState>
      provider;

  /// Called when the user confirms deletion. Should return true on success.
  final Future<bool> Function() onClear;

  /// Description of what will be deleted, used in the confirmation dialog.
  final String clearDescription;

  const StorageUsageWidget({
    super.key,
    required this.provider,
    required this.onClear,
    required this.clearDescription,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: state.isLoading
                ? null
                : () => ref.read(provider.notifier).refresh(),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(8),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else if (state.error != null)
                    Icon(Icons.error_outline,
                        size: 14, color: colorScheme.error)
                  else
                    Icon(Icons.cloud,
                        size: 14,
                        color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    state.isLoading ? '...' : state.displaySize,
                    style: TextStyle(
                      fontSize: 12,
                      color: state.error != null
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Vertical divider between storage and delete button
        Container(
          width: 1,
          height: 16,
          color: colorScheme.outlineVariant.withAlpha(80),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: state.isLoading
                ? null
                : () => _showClearDialog(context, ref),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Icon(
                Icons.delete_outline,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showClearDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCountdownConfirmDialog(
      context: context,
      title: '确认删除',
      message: '此操作将清空$clearDescription，不可恢复。',
      confirmLabel: '删除',
    );

    if (confirmed && context.mounted) {
      final success = await onClear();
      if (context.mounted) {
        ref.read(provider.notifier).refresh();
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败，请重试')),
          );
        }
      }
    }
  }
}
