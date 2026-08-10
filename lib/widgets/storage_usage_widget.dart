import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/webdav_provider.dart';

/// A compact widget showing WebDAV storage usage, shared by Text Bridge
/// and File Depot. Tap to refresh.
class StorageUsageWidget extends ConsumerWidget {
  final StateNotifierProvider<StorageUsageNotifier, StorageUsageState>
      provider;

  const StorageUsageWidget({super.key, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: state.isLoading
            ? null
            : () => ref.read(provider.notifier).refresh(),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else if (state.error != null)
                Icon(Icons.error_outline, size: 14, color: colorScheme.error)
              else
                Icon(Icons.cloud_outlined,
                    size: 14, color: colorScheme.onSurfaceVariant),
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
    );
  }
}
