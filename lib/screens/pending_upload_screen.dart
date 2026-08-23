import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/server_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/pending_upload_provider.dart';
import '../providers/upload_queue_provider.dart';

/// Full-screen page shown in "pending" drag mode.
/// Files are displayed as horizontal thumbnails; enabled servers as a vertical list.
class PendingUploadScreen extends ConsumerWidget {
  final VoidCallback onClose;

  const PendingUploadScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingUploadProvider);
    final enabledServers = ref.watch(enabledServersProvider);
    final activeServer = ref.watch(activeFilesServerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pendingUploadTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(pendingUploadProvider.notifier).clear();
            onClose();
          },
        ),
        actions: [
          if (activeServer != null)
            Tooltip(
              message: l10n.currentServerLabel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activeServer.emoji.isNotEmpty)
                      Text(
                        activeServer.emoji,
                        style: const TextStyle(fontSize: 18),
                      )
                    else
                      Icon(Icons.cloud, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        activeServer.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            onPressed: pending.filePaths.isEmpty || activeServer == null
                ? null
                : () => _uploadToServer(ref, activeServer),
            icon: Icon(Icons.send, color: colorScheme.primary),
            tooltip: l10n.uploadToServer,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              // File selection card (matching LocalSend style)
              if (pending.filePaths.isNotEmpty)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              l10n.selectedFilesLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(l10n.fileCountLabel(pending.filePaths.length)),
                        FutureBuilder<int>(
                          future: _totalSize(pending.filePaths),
                          builder: (ctx, snap) {
                            final bytes = snap.data ?? 0;
                            return Text(
                              l10n.totalSizeLabel(_formatSize(bytes)),
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.outline,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 54,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: pending.filePaths.length,
                            itemBuilder: (context, index) {
                              final path = pending.filePaths[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _SimpleThumbnail(
                                  path: path,
                                  onRemove: () => ref
                                      .read(pendingUploadProvider.notifier)
                                      .removeFile(path),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Server list header
              if (enabledServers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.selectServerLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),

              // Server list
              Expanded(
                child: pending.filePaths.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_upload_outlined,
                              size: 48,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.dropFilesToStart,
                              style: TextStyle(color: colorScheme.outline),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: enabledServers.length,
                        itemBuilder: (context, index) {
                          final server = enabledServers[index];
                          final isActive = server.id == activeServer?.id;
                          return Card(
                            color: isActive
                                ? colorScheme.primaryContainer
                                : null,
                            child: ListTile(
                              leading: SizedBox(
                                width: 24,
                                child: server.emoji.isNotEmpty
                                    ? Text(
                                        server.emoji,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 18),
                                      )
                                    : Icon(
                                        Icons.cloud,
                                        size: 20,
                                        color: colorScheme.primary,
                                      ),
                              ),
                              title: Text(
                                server.name,
                                style: TextStyle(
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                server.serverUrl,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.outline,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isActive)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Text(
                                        l10n.currentServerLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  Icon(Icons.send, color: colorScheme.primary),
                                ],
                              ),
                              onTap: () => _uploadToServer(ref, server),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int> _totalSize(List<String> paths) async {
    int total = 0;
    for (final path in paths) {
      try {
        final entityType = await FileSystemEntity.type(path);
        if (entityType == FileSystemEntityType.file) {
          total += await File(path).length();
        } else if (entityType == FileSystemEntityType.directory) {
          await for (final entity in Directory(path).list(recursive: true)) {
            if (entity is File) total += await entity.length();
          }
        }
      } catch (_) {}
    }
    return total;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _uploadToServer(WidgetRef ref, ServerConfig server) async {
    final paths = List<String>.from(ref.read(pendingUploadProvider).filePaths);
    if (paths.isEmpty) return;

    // Switch to target server if not current
    final currentFilesId = ref
        .read(configProvider)
        .valueOrNull
        ?.activeFilesServerId;
    if (currentFilesId != server.id) {
      await ref.read(configProvider.notifier).switchFilesServer(server.id);
    }

    // Add files and folders to the upload queue.
    final files = <String>[];
    final folders = <String>[];
    for (final path in paths) {
      final entityType = await FileSystemEntity.type(path);
      if (entityType == FileSystemEntityType.directory) {
        folders.add(path);
      } else if (entityType == FileSystemEntityType.file) {
        files.add(path);
      }
    }

    if (files.isNotEmpty) {
      await ref.read(uploadQueueProvider.notifier).addFiles(files);
    }
    for (final folder in folders) {
      await ref.read(uploadQueueProvider.notifier).addFolder(folder);
    }

    ref.read(pendingUploadProvider.notifier).clear();
    onClose();
  }
}

class _SimpleThumbnail extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _SimpleThumbnail({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(path).toLowerCase();
    final isDirectory = Directory(path).existsSync();
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ColoredBox(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                isDirectory ? Icons.folder : _iconForExtension(ext),
                size: 28,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(9),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 2),
                  ],
                ),
                child: Icon(Icons.close, size: 12, color: colorScheme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForExtension(String ext) {
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
        return Icons.image;
      case '.mp4':
      case '.mkv':
      case '.mov':
      case '.avi':
        return Icons.videocam;
      case '.mp3':
      case '.wav':
      case '.flac':
        return Icons.audiotrack;
      case '.zip':
      case '.rar':
      case '.7z':
        return Icons.folder_zip;
      case '.apk':
        return Icons.android;
      case '.txt':
      case '.md':
      case '.json':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }
}
