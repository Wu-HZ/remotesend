import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/server_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/camera_capture_provider.dart';
import '../providers/pending_upload_provider.dart';
import '../providers/upload_queue_provider.dart';

/// Full-screen page shown in "pending" drag mode.
/// Files are displayed as horizontal thumbnails; enabled servers as a vertical list.
class PendingUploadScreen extends ConsumerStatefulWidget {
  const PendingUploadScreen({super.key});

  @override
  ConsumerState<PendingUploadScreen> createState() =>
      _PendingUploadScreenState();
}

class _PendingUploadScreenState extends ConsumerState<PendingUploadScreen> {
  bool _isPicking = false;

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingUploadProvider);
    final enabledServers = ref.watch(enabledServersProvider);
    final activeServer = ref.watch(activeFilesServerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final cameraSupported = ref.watch(cameraSupportedProvider);
    final busy =
        _isPicking ||
        pending.isSubmitting ||
        ref.watch(cameraCaptureProvider).isBusy;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pendingUploadTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: busy
              ? null
              : () {
                  ref.read(pendingUploadProvider.notifier).clear();
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
            onPressed: busy || pending.filePaths.isEmpty || activeServer == null
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
              if (busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (cameraSupported)
                      FilledButton.tonalIcon(
                        onPressed: busy
                            ? null
                            : () => ref
                                  .read(cameraCaptureProvider.notifier)
                                  .capture(),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(l10n.takeAnotherPhoto),
                      ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _pickFiles,
                      icon: const Icon(Icons.attach_file),
                      label: Text(l10n.addPendingFiles),
                    ),
                  ],
                ),
              ),
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
                                  onRemove: busy
                                      ? null
                                      : () => ref
                                            .read(
                                              pendingUploadProvider.notifier,
                                            )
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
                      l10n.sendToServerLabel,
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
                              onTap: busy
                                  ? null
                                  : () => _uploadToServer(ref, server),
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
        final stat = await FileStat.stat(path);
        if (stat.type == FileSystemEntityType.file) {
          total += stat.size;
        } else if (stat.type == FileSystemEntityType.directory) {
          await for (final entity in Directory(path).list(recursive: true)) {
            if (entity is File) total += (await entity.stat()).size;
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

  Future<void> _pickFiles() async {
    setState(() => _isPicking = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (!mounted || result == null) return;
      final paths = result.files
          .map((file) => file.path)
          .whereType<String>()
          .toList();
      ref.read(pendingUploadProvider.notifier).addFiles(paths);
      if (paths.length != result.files.length) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.couldNotAccessFiles)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.error(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _uploadToServer(WidgetRef ref, ServerConfig server) async {
    final pending = ref.read(pendingUploadProvider.notifier);
    final paths = pending.beginSubmission();
    if (paths.isEmpty) return;
    final unsubmitted = List<String>.from(paths);
    final l10n = AppLocalizations.of(context)!;
    try {
      final currentFilesId = ref
          .read(configProvider)
          .valueOrNull
          ?.activeFilesServerId;
      if (currentFilesId != server.id) {
        final switched = await ref
            .read(configProvider.notifier)
            .switchFilesServer(server.id);
        if (!switched) throw StateError(l10n.switchServer);
      }
      if (!mounted) return;

      final files = <String>[];
      final folders = <String>[];
      for (final path in paths) {
        final entityType = await FileSystemEntity.type(path);
        if (entityType == FileSystemEntityType.directory) {
          folders.add(path);
        } else if (entityType == FileSystemEntityType.file) {
          files.add(path);
        } else {
          throw FileSystemException(l10n.couldNotAccessFiles, path);
        }
      }
      if (!mounted) return;
      final queue = ref.read(uploadQueueProvider.notifier);
      if (files.isNotEmpty) {
        await queue.addFiles(files);
        unsubmitted.removeWhere(files.contains);
      }
      for (final folder in folders) {
        await queue.addFolder(folder);
        unsubmitted.remove(folder);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.error(e.toString()))));
      }
    } finally {
      pending.finishSubmission(unsubmitted: unsubmitted);
    }
  }
}

class _SimpleThumbnail extends StatelessWidget {
  final String path;
  final VoidCallback? onRemove;

  const _SimpleThumbnail({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(path).toLowerCase();
    final isDirectory = Directory(path).existsSync();
    final colorScheme = Theme.of(context).colorScheme;
    final isImage =
        !isDirectory &&
        {
          '.jpg',
          '.jpeg',
          '.png',
          '.gif',
          '.webp',
          '.heic',
          '.heif',
        }.contains(ext);
    final fallback = Icon(
      isDirectory ? Icons.folder : _iconForExtension(ext),
      size: 28,
      color: colorScheme.primary,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: p.basename(path),
          child: InkWell(
            onTap: isImage ? () => _preview(context) : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: isImage
                      ? Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          errorBuilder: (_, _, _) => fallback,
                        )
                      : fallback,
                ),
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

  void _preview(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.9,
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              ListTile(
                title: Text(p.basename(path), overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: l10n.close,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      File(path),
                      cacheWidth: 2048,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Text(l10n.photoPreviewUnavailable),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
