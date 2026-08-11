import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/server_config.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text('待上传 (${pending.filePaths.length} 个文件)'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(pendingUploadProvider.notifier).clear();
            onClose();
          },
        ),
      ),
      body: Column(
        children: [
          // File thumbnails section
          if (pending.filePaths.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '已选文件',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            ref.read(pendingUploadProvider.notifier).clear(),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: pending.filePaths.length,
                      itemBuilder: (context, index) {
                        final path = pending.filePaths[index];
                        final name = p.basename(path);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FileThumbnail(
                            path: path,
                            name: name,
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

          // Quick send to last used server
          if (pending.filePaths.isNotEmpty && enabledServers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _uploadToServer(
                    ref,
                    activeServer ?? enabledServers.first,
                  ),
                  icon: const Icon(Icons.bolt),
                  label: Text(
                    '传到 ${activeServer != null ? activeServer!.name : enabledServers.first.name}',
                  ),
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
                  '选择服务器',
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
                        Icon(Icons.cloud_upload_outlined,
                            size: 48, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('拖入文件开始',
                            style: TextStyle(color: colorScheme.outline)),
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
                        child: ListTile(
                          leading: server.emoji.isNotEmpty
                              ? Text(server.emoji,
                                  style: const TextStyle(fontSize: 24))
                              : Icon(Icons.cloud,
                                  color: colorScheme.primary),
                          title: Text(server.name,
                              style: TextStyle(
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              )),
                          subtitle: Text(server.serverUrl,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.outline)),
                          trailing: Icon(Icons.send,
                              color: colorScheme.primary),
                          onTap: () => _uploadToServer(ref, server),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadToServer(
      WidgetRef ref, ServerConfig server) async {
    final paths =
        List<String>.from(ref.read(pendingUploadProvider).filePaths);
    if (paths.isEmpty) return;

    // Switch to target server if not current
    final currentFilesId =
        ref.read(configProvider).valueOrNull?.activeFilesServerId;
    if (currentFilesId != server.id) {
      await ref.read(configProvider.notifier).switchFilesServer(server.id);
    }

    // Add to upload queue
    await ref.read(uploadQueueProvider.notifier).addFiles(paths);
    ref.read(pendingUploadProvider.notifier).clear();
    onClose();
  }
}

class _FileThumbnail extends StatelessWidget {
  final String path;
  final String name;
  final VoidCallback onRemove;

  const _FileThumbnail({
    required this.path,
    required this.name,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(path).toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Container(
          width: 72,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _iconForExtension(ext),
                size: 28,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
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
