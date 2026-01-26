import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/upload_queue.dart';
import '../models/download_queue.dart';
import '../providers/config_provider.dart';
import '../providers/upload_queue_provider.dart';
import '../providers/download_state_provider.dart';

/// Screen for viewing and managing the transfer queue (uploads and downloads).
class TransferQueueScreen extends ConsumerStatefulWidget {
  const TransferQueueScreen({super.key});

  @override
  ConsumerState<TransferQueueScreen> createState() => _TransferQueueScreenState();
}

class _TransferQueueScreenState extends ConsumerState<TransferQueueScreen> {
  String? _downloadLocation;

  @override
  void initState() {
    super.initState();
    _initDownloadLocation();
  }

  Future<void> _initDownloadLocation() async {
    final config = ref.read(configProvider).valueOrNull;
    if (config != null && config.downloadLocation.isNotEmpty) {
      _downloadLocation = config.downloadLocation;
    } else {
      _downloadLocation = await _getSystemDownloadDirectory();
    }
    if (mounted) setState(() {});
  }

  Future<String?> _getSystemDownloadDirectory() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        return p.join(userProfile, 'Downloads');
      }
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return p.join(home, 'Downloads');
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return p.join(home, 'Downloads');
      }
    } else if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      return dir?.path;
    }
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _openDownloadFolder() async {
    if (_downloadLocation == null) return;

    final l10n = AppLocalizations.of(context)!;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [_downloadLocation!]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_downloadLocation!]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [_downloadLocation!]);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.openFileFolderNotSupported)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToOpenFolder(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openFile(String filePath) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.fileNotFound), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (Platform.isWindows) {
        // Open the file directly with default application
        await Process.run('cmd', ['/c', 'start', '', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [filePath]);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.openFileNotSupported)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToOpenFile(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final uploadState = ref.watch(uploadQueueProvider);
    final downloadState = ref.watch(downloadStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.transferQueue),
        actions: [
          // Open download folder button
          IconButton(
            onPressed: _openDownloadFolder,
            icon: const Icon(Icons.folder_open),
            tooltip: l10n.openDownloadFolder,
          ),
          if (uploadState.failedCount > 0)
            IconButton(
              onPressed: () => ref.read(uploadQueueProvider.notifier).retryFailed(),
              icon: const Icon(Icons.refresh),
              tooltip: l10n.retryFailed,
            ),
          if (uploadState.completedCount > 0)
            IconButton(
              onPressed: () => ref.read(uploadQueueProvider.notifier).clearCompleted(),
              icon: const Icon(Icons.clear_all),
              tooltip: l10n.clearCompleted,
            ),
          if (uploadState.items.isNotEmpty)
            IconButton(
              onPressed: () => _confirmClearAll(context, l10n),
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.clearAll,
            ),
        ],
      ),
      body: _buildBody(context, l10n, uploadState, downloadState),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, UploadQueueState uploadState, DownloadState downloadState) {
    final hasDownloads = downloadState.items.isNotEmpty || downloadState.isDownloading || downloadState.error != null;
    final hasUploads = uploadState.items.isNotEmpty;

    if (!hasDownloads && !hasUploads) {
      return _buildEmptyState(context, l10n);
    }

    return ListView(
      children: [
        // Download section with items
        if (hasDownloads) ...[
          _buildDownloadSection(context, l10n, downloadState),
          ...downloadState.items.map((item) => _buildDownloadItem(context, l10n, item)),
          if (downloadState.items.isNotEmpty) const Divider(height: 1),
        ],

        // Upload section with items
        _buildUploadSection(context, l10n, uploadState),
        ...uploadState.items.map((item) => _buildUploadItem(context, l10n, item)),
      ],
    );
  }

  Widget _buildDownloadSection(BuildContext context, AppLocalizations l10n, DownloadState state) {
    final isActive = state.isDownloading;
    final progressPercent = (state.progress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      color: isActive
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Icon(
                _getDownloadStatusIcon(state.statusText),
                color: isActive
                    ? Theme.of(context).colorScheme.onSecondaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.downloadStatus(state.statusText),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (state.isFolderDownload)
                Text(
                  l10n.filesProgress(state.currentFileIndex, state.totalFiles),
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),

          if (state.fileName != null || state.totalBytes > 0) ...[
            const SizedBox(height: 12),

            // File name row
            if (state.fileName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  state.fileName!,
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Size and speed row
            Row(
              children: [
                Text(
                  '${state.displayDownloadedSize} / ${state.displayTotalSize}',
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Text(
                    state.displaySpeed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(width: 16),
                Text(
                  '$progressPercent%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? Theme.of(context).colorScheme.onSecondaryContainer
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
                  _buildDownloadTimeInfo(
                    context,
                    l10n.elapsed,
                    state.displayElapsedTime,
                  ),
                  const SizedBox(width: 16),
                  // Estimated duration
                  _buildDownloadTimeInfo(
                    context,
                    l10n.duration,
                    state.displayEstimatedDuration,
                  ),
                  const Spacer(),
                  // Remaining time (highlighted)
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        state.displayRemainingTime,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.remaining,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondaryContainer.withAlpha(180),
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
              value: state.progress,
              backgroundColor: isActive
                  ? Theme.of(context).colorScheme.onSecondaryContainer.withAlpha(50)
                  : Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(50),
            ),
          ],

          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getDownloadStatusIcon(String status) {
    switch (status) {
      case 'Downloading':
        return Icons.download;
      case 'Completed':
        return Icons.check_circle;
      case 'Failed':
        return Icons.error;
      default:
        return Icons.hourglass_empty;
    }
  }

  Widget _buildDownloadTimeInfo(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSecondaryContainer.withAlpha(150),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      ],
    );
  }

  Widget _buildUploadSection(BuildContext context, AppLocalizations l10n, UploadQueueState state) {
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
                l10n.uploadStatus(state.statusText),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (state.items.isNotEmpty)
                Text(
                  l10n.filesProgress(state.completedCount, state.items.length),
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
                    l10n.elapsed,
                    state.displayElapsedTime,
                    isActive,
                  ),
                  const SizedBox(width: 16),
                  // Estimated duration
                  _buildTimeInfo(
                    context,
                    l10n.duration,
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
                        l10n.remaining,
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

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sync_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.transferQueueEmpty,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.filesWillAppearHere,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadItem(BuildContext context, AppLocalizations l10n, UploadItem item) {
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
            '${item.displaySize} • ${_getStatusText(l10n, item.status)}',
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

  String _getStatusText(AppLocalizations l10n, UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return l10n.statusPending;
      case UploadStatus.uploading:
        return l10n.statusUploading;
      case UploadStatus.completed:
        return l10n.statusCompleted;
      case UploadStatus.failed:
        return l10n.statusFailed;
    }
  }

  Widget _buildDownloadItem(BuildContext context, AppLocalizations l10n, DownloadItem item) {
    return ListTile(
      leading: _buildDownloadItemStatusIcon(context, item),
      title: Text(
        item.fileName,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.displaySize} • ${_getDownloadStatusText(l10n, item.status)}',
            style: TextStyle(
              fontSize: 12,
              color: item.status == DownloadStatus.failed
                  ? Colors.red
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          if (item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.completed) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: item.progress,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: Theme.of(context).colorScheme.secondary,
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
      trailing: _buildDownloadItemTrailing(context, l10n, item),
    );
  }

  Widget? _buildDownloadItemTrailing(BuildContext context, AppLocalizations l10n, DownloadItem item) {
    if (item.status == DownloadStatus.downloading) {
      return Text(
        '${(item.progress * 100).toStringAsFixed(0)}%',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.secondary,
        ),
      );
    } else if (item.status == DownloadStatus.completed) {
      return IconButton(
        onPressed: () => _openFile(item.localPath),
        icon: const Icon(Icons.open_in_new),
        tooltip: l10n.openFile,
        visualDensity: VisualDensity.compact,
      );
    }
    return null;
  }

  Widget _buildDownloadItemStatusIcon(BuildContext context, DownloadItem item) {
    switch (item.status) {
      case DownloadStatus.pending:
        return Icon(
          Icons.schedule,
          color: Theme.of(context).colorScheme.outline,
        );
      case DownloadStatus.downloading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: item.progress,
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.secondary,
          ),
        );
      case DownloadStatus.completed:
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
        );
      case DownloadStatus.failed:
        return const Icon(
          Icons.error,
          color: Colors.red,
        );
    }
  }

  String _getDownloadStatusText(AppLocalizations l10n, DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return l10n.statusPending;
      case DownloadStatus.downloading:
        return l10n.statusDownloading;
      case DownloadStatus.completed:
        return l10n.statusCompleted;
      case DownloadStatus.failed:
        return l10n.statusFailed;
    }
  }

  void _confirmClearAll(BuildContext context, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearQueue),
        content: Text(l10n.clearQueueConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(uploadQueueProvider.notifier).clearAll();
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.clearAll),
          ),
        ],
      ),
    );
  }
}
