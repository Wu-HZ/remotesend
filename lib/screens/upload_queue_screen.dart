import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/upload_queue.dart';
import '../providers/upload_queue_provider.dart';

/// Screen for viewing and managing the upload queue.
class UploadQueueScreen extends ConsumerWidget {
  const UploadQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueState = ref.watch(uploadQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [
          if (queueState.failedCount > 0)
            IconButton(
              onPressed: () => ref.read(uploadQueueProvider.notifier).retryFailed(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry failed',
            ),
          if (queueState.completedCount > 0)
            IconButton(
              onPressed: () => ref.read(uploadQueueProvider.notifier).clearCompleted(),
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear completed',
            ),
          if (queueState.items.isNotEmpty)
            IconButton(
              onPressed: () => _confirmClearAll(context, ref),
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: Column(
        children: [
          // Total progress section
          _buildTotalProgress(context, queueState),

          const Divider(height: 1),

          // File list
          Expanded(
            child: queueState.items.isEmpty
                ? _buildEmptyState(context)
                : _buildFileList(context, queueState),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalProgress(BuildContext context, UploadQueueState state) {
    final isActive = state.isProcessing;
    final progressPercent = (state.overallProgress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      color: isActive
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Icon(
                _getStatusIcon(state.statusText),
                color: isActive
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                state.statusText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (state.items.isNotEmpty)
                Text(
                  '${state.completedCount}/${state.items.length} files',
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),

          if (state.items.isNotEmpty) ...[
            const SizedBox(height: 12),

            // Size and speed row
            Row(
              children: [
                Text(
                  '${state.displayUploadedSize} / ${state.displayTotalSize}',
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Text(
                    state.displaySpeed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(width: 16),
                Text(
                  '$progressPercent%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // Time info row (only when active)
            if (isActive) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  // Elapsed time
                  _buildTimeInfo(
                    context,
                    'Elapsed',
                    state.displayElapsedTime,
                    isActive,
                  ),
                  const SizedBox(width: 16),
                  // Estimated duration
                  _buildTimeInfo(
                    context,
                    'Duration',
                    state.displayEstimatedDuration,
                    isActive,
                  ),
                  const Spacer(),
                  // Remaining time (highlighted)
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        state.displayRemainingTime,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'remaining',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withAlpha(180),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // Progress bar
            LinearProgressIndicator(
              value: state.overallProgress,
              backgroundColor: isActive
                  ? Theme.of(context).colorScheme.onPrimaryContainer.withAlpha(50)
                  : Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(50),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Uploading':
        return Icons.upload;
      case 'Completed':
        return Icons.check_circle;
      case 'Failed':
        return Icons.error;
      default:
        return Icons.hourglass_empty;
    }
  }

  Widget _buildTimeInfo(BuildContext context, String label, String value, bool isActive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onPrimaryContainer.withAlpha(150),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Upload queue is empty',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Files will appear here when you start uploading',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(BuildContext context, UploadQueueState state) {
    return ListView.builder(
      itemCount: state.items.length,
      itemBuilder: (context, index) {
        final item = state.items[index];
        return _buildFileItem(context, item);
      },
    );
  }

  Widget _buildFileItem(BuildContext context, UploadItem item) {
    return ListTile(
      leading: _buildStatusIcon(context, item),
      title: Text(
        item.fileName,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.displaySize} • ${_getStatusText(item.status)}',
            style: TextStyle(
              fontSize: 12,
              color: item.status == UploadStatus.failed
                  ? Colors.red
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          if (item.status == UploadStatus.uploading ||
              item.status == UploadStatus.completed) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: item.progress,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ],
          if (item.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.error!,
                style: const TextStyle(fontSize: 11, color: Colors.red),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: item.status == UploadStatus.uploading
          ? Text(
              '${(item.progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : null,
    );
  }

  Widget _buildStatusIcon(BuildContext context, UploadItem item) {
    switch (item.status) {
      case UploadStatus.pending:
        return Icon(
          Icons.schedule,
          color: Theme.of(context).colorScheme.outline,
        );
      case UploadStatus.uploading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: item.progress,
            strokeWidth: 2,
          ),
        );
      case UploadStatus.completed:
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
        );
      case UploadStatus.failed:
        return const Icon(
          Icons.error,
          color: Colors.red,
        );
    }
  }

  String _getStatusText(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return 'Pending';
      case UploadStatus.uploading:
        return 'Uploading';
      case UploadStatus.completed:
        return 'Completed';
      case UploadStatus.failed:
        return 'Failed';
    }
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue'),
        content: const Text(
          'Are you sure you want to clear the entire upload queue? '
          'This will cancel any ongoing uploads.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(uploadQueueProvider.notifier).clearAll();
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
