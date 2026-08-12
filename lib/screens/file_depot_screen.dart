import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';
import '../providers/upload_queue_provider.dart';
import '../providers/download_state_provider.dart';
import '../providers/pending_upload_provider.dart';
import '../services/webdav_service.dart';
import '../widgets/storage_usage_widget.dart';
import 'pending_upload_screen.dart';
import 'transfer_queue_screen.dart';

/// File Depot screen for uploading and downloading files via WebDAV.
class FileDepotScreen extends ConsumerStatefulWidget {
  const FileDepotScreen({super.key});

  @override
  ConsumerState<FileDepotScreen> createState() => _FileDepotScreenState();
}

class _FileDepotScreenState extends ConsumerState<FileDepotScreen> {
  String? _currentDownloadLocation;
  final _scrollController = ScrollController();
  bool _fabVisible = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(_initialLoad);
  }

  Future<void> _initialLoad() async {
    final connectionStatus = ref.read(filesConnectionStatusProvider);
    if (connectionStatus.state == WebDavConnectionState.connected) {
      ref.read(fileListProvider.notifier).refresh();
    }
    // Initialize download location
    await _initDownloadLocation();
  }

  Future<void> _initDownloadLocation() async {
    final config = ref.read(configProvider).valueOrNull;
    if (config != null && config.downloadLocation.isNotEmpty) {
      _currentDownloadLocation = config.downloadLocation;
    } else {
      _currentDownloadLocation = await _getSystemDownloadDirectory();
    }
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if (direction == ScrollDirection.forward && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<String?> _getSystemDownloadDirectory() async {
    if (Platform.isWindows) {
      // Windows: Use user's Downloads folder
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
      // On Android, use external storage Downloads or app's external storage
      final dir = await getExternalStorageDirectory();
      return dir?.path;
    }
    // Fallback to app documents directory
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _openFolderAndroid(String path) async {
    const authority = 'com.remotesend.remote_send.fileprovider';
    const externalStorageRoot = '/storage/emulated/0';
    final String contentUri;
    if (path.startsWith(externalStorageRoot)) {
      final relative = path.substring(externalStorageRoot.length);
      contentUri = 'content://$authority/external$relative';
    } else {
      contentUri = 'content://$authority/root$path';
    }
    await launchUrl(Uri.parse(contentUri), mode: LaunchMode.externalApplication);
  }

  Future<void> _openDownloadLocation() async {
    if (_currentDownloadLocation == null) return;

    final l10n = AppLocalizations.of(context)!;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [_currentDownloadLocation!]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_currentDownloadLocation!]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [_currentDownloadLocation!]);
      } else if (Platform.isAndroid) {
        await _openFolderAndroid(_currentDownloadLocation!);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isConfigured = ref.watch(isFilesConfiguredProvider);
    final connectionStatus = ref.watch(filesConnectionStatusProvider);
    final fileListState = ref.watch(fileListProvider);
    final config = ref.watch(configProvider).valueOrNull;
    final activeServer = ref.watch(activeFilesServerProvider);
    final servers = ref.watch(enabledServersProvider);
    final pendingFiles = ref.watch(pendingUploadProvider);

    // Show pending upload page if there are files waiting
    if (pendingFiles.filePaths.isNotEmpty) {
      return _buildPendingUploadView(l10n);
    }

    // Update download location if config changed
    if (config != null) {
      final configLocation = config.downloadLocation.isNotEmpty
          ? config.downloadLocation
          : null;
      if (configLocation != null && configLocation != _currentDownloadLocation) {
        _currentDownloadLocation = configLocation;
      }
    }

    final isConnected = connectionStatus.state == WebDavConnectionState.connected;
    final isConnecting = connectionStatus.state == WebDavConnectionState.connecting;
    final canOperate = isConfigured && (isConnected || isConnecting);

    ref.listen(filesConnectionStatusProvider, (prev, next) {
      if (prev?.state != WebDavConnectionState.connected &&
          next.state == WebDavConnectionState.connected) {
        ref.read(fileListProvider.notifier).refresh();
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            if (canOperate) StorageUsageWidget(
              provider: filesStorageUsageProvider,
              clearDescription:
                  l10n.clearAllFiles(activeServer?.name ?? ''),
              onClear: () async {
                final service = ref.read(webDavFilesServiceProvider);
                final result = await service.clearAllFiles();
                if (result.isSuccess) {
                  ref.read(fileListProvider.notifier).refresh();
                }
                return result.isSuccess;
              },
            ),
            const Spacer(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.fileDepot),
                if (!fileListState.isAtRoot)
                  Text(
                    fileListState.currentPathDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const Spacer(),
          ],
        ),
        actions: [
          // Server selector
          if (servers.isNotEmpty)
            _buildServerSelector(l10n, activeServer, servers),
          // Open download folder button
          if (_currentDownloadLocation != null)
            IconButton(
              onPressed: _openDownloadLocation,
              icon: const Icon(Icons.folder_open),
              tooltip: l10n.openDownloadFolder,
            ),
          IconButton(
            onPressed: canOperate && !fileListState.isLoading
                ? () => ref.read(fileListProvider.notifier).refresh()
                : null,
            icon: fileListState.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              // Connection warning banner
              if (!canOperate) _buildWarningBanner(l10n, isConfigured, connectionStatus.state),

          // Status indicator (always visible)
          _buildStatusIndicator(l10n),

          // Error message
          if (fileListState.error != null) _buildErrorCard(fileListState.error!),

          // File list
          Expanded(
            child: _buildFileList(l10n, fileListState, canOperate),
          ),
            ],
          ),
        ),
      ),
      floatingActionButton: canOperate
          ? IgnorePointer(
              ignoring: !_fabVisible,
              child: AnimatedSlide(
                offset: _fabVisible ? Offset.zero : const Offset(0, 1.5),
                duration: const Duration(milliseconds: 200),
                child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'folder',
                  onPressed: _pickAndUploadFolder,
                  icon: const Icon(Icons.folder),
                  label: Text(l10n.folder),
                ),
                const SizedBox(width: 12),
                FloatingActionButton.extended(
                  heroTag: 'file',
                  onPressed: _pickAndUploadFiles,
                  icon: const Icon(Icons.insert_drive_file),
                  label: Text(l10n.file),
                ),
              ],
            ),
          ),
        )
          : null,
    );
  }

  Widget _buildServerSelector(AppLocalizations l10n, ServerConfig? activeServer, List<ServerConfig> servers) {
    return PopupMenuButton<String>(
      tooltip: l10n.switchServer,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activeServer != null && activeServer!.emoji.isNotEmpty)
            Text(activeServer!.emoji, style: const TextStyle(fontSize: 16))
          else
            Icon(
              Icons.cloud,
              size: 18,
              color: activeServer != null ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
      onSelected: (serverId) async {
        ref.read(configProvider.notifier).switchFilesServer(serverId);
        await ref.read(filesConnectionStatusProvider.notifier).testConnection();
      },
      itemBuilder: (context) => servers.map((server) {
        final isActive = server.id == activeServer?.id;
        return PopupMenuItem<String>(
          value: server.id,
          child: Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isActive ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                child: server.emoji.isNotEmpty
                    ? Text(server.emoji,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16))
                    : Icon(Icons.cloud,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  server.name,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPendingUploadView(AppLocalizations l10n) {
    return PendingUploadScreen(
      onClose: () {
        ref.read(pendingUploadProvider.notifier).clear();
      },
    );
  }

  Widget _buildWarningBanner(AppLocalizations l10n, bool isConfigured,
      WebDavConnectionState connectionState) {
    String message;
    IconData icon;

    if (!isConfigured) {
      message = l10n.configureWebDavToUseFileDepot;
      icon = Icons.settings;
    } else if (connectionState == WebDavConnectionState.error) {
      message = l10n.notConnectedTestInSettings;
      icon = Icons.cloud_off;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withAlpha(30),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(AppLocalizations l10n) {
    final queueState = ref.watch(uploadQueueProvider);
    final downloadState = ref.watch(downloadStateProvider);
    final isUploading = queueState.isProcessing;
    final isDownloading = downloadState.isDownloading;
    final isActive = isUploading || isDownloading;

    // Determine status text and icon
    String statusText;
    IconData statusIcon;
    double progress;
    String? speedText;

    if (isDownloading) {
      if (downloadState.isFolderDownload) {
        statusText = l10n.downloadingFileWithProgress(downloadState.fileName ?? '', downloadState.currentFileIndex, downloadState.totalFiles);
      } else {
        statusText = l10n.downloadingFile(downloadState.fileName ?? '');
      }
      statusIcon = Icons.download;
      progress = downloadState.progress;
      if (downloadState.currentSpeed > 0) {
        speedText = downloadState.displaySpeed;
      }
    } else if (isUploading) {
      final currentItem = queueState.currentItem;
      if (currentItem != null) {
        statusText = l10n.uploadingFile(currentItem.fileName, queueState.completedCount + 1, queueState.items.length);
        progress = queueState.overallProgress;
      } else {
        statusText = l10n.uploadingEllipsis;
        progress = queueState.overallProgress;
      }
      statusIcon = Icons.upload;
      if (queueState.currentSpeed > 0) {
        speedText = queueState.displaySpeed;
      }
    } else if (queueState.items.isNotEmpty) {
      final fc = queueState.failedCount;
      if (fc > 0) {
        statusText = '${l10n.filesUploaded(queueState.completedCount, queueState.items.length)} ($fc failed)';
        statusIcon = Icons.warning_amber;
      } else {
        statusText = l10n.filesUploaded(queueState.completedCount, queueState.items.length);
        statusIcon = Icons.check_circle;
      }
      progress = 1.0;
    } else if (downloadState.items.isNotEmpty && !downloadState.isDownloading) {
      final isFailed = downloadState.error != null;
      if (isFailed) {
        statusText = downloadState.error ?? l10n.downloadFailed;
        statusIcon = Icons.error;
      } else {
        statusText = l10n.filesDownloaded(downloadState.completedCount, downloadState.items.length);
        statusIcon = Icons.check_circle;
      }
      progress = 1.0;
    } else {
      statusText = l10n.idle;
      statusIcon = Icons.hourglass_empty;
      progress = 0;
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TransferQueueScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  statusIcon,
                  size: 20,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: isActive
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive) ...[
                  if (speedText != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        speedText,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Colors.red.withAlpha(25),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(error, style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(AppLocalizations l10n, FileListState fileListState, bool canOperate) {
    if (!canOperate) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l10n.connectToWebDavToViewFiles),
          ],
        ),
      );
    }

    if (fileListState.isLoading && fileListState.files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (fileListState.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              fileListState.isAtRoot ? l10n.noFilesYet : l10n.emptyFolder,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fileListState.isAtRoot
                  ? l10n.tapFileOrFolderToUpload
                  : l10n.thisFolderIsEmpty,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(fileListProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 80),
        itemCount:
            fileListState.files.length + (fileListState.isAtRoot ? 0 : 1),
        itemBuilder: (context, index) {
          if (!fileListState.isAtRoot && index == 0) {
            return ListTile(
              leading: const Icon(Icons.subdirectory_arrow_left),
              title: Text('..', style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => ref.read(fileListProvider.notifier).navigateUp(),
            );
          }
          final fileIndex = fileListState.isAtRoot ? index : index - 1;
          final file = fileListState.files[fileIndex];
          return _buildFileItem(l10n, file);
        },
      ),
    );
  }

  Widget _buildFileItem(AppLocalizations l10n, RemoteFile file) {
    final isDirectory = file.isDirectory;

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(l10n, details.globalPosition, file),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDirectory
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isDirectory ? Icons.folder : _getFileIcon(file.name),
            color: isDirectory ? Theme.of(context).colorScheme.primary : null,
            size: 22,
          ),
        ),
        title: Text(
          file.name,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _buildSubtitle(l10n, file),
          style: TextStyle(
            color: Theme.of(context).colorScheme.outline,
            fontSize: 12,
          ),
        ),
        trailing: isDirectory
            ? const Icon(Icons.chevron_right)
            : PopupMenuButton<String>(
                onSelected: (value) => _handleFileAction(l10n, value, file),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        const Icon(Icons.download),
                        const SizedBox(width: 8),
                        Text(l10n.download),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(l10n.delete, style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
        onTap: isDirectory
            ? () => ref.read(fileListProvider.notifier).navigateToFolder(file.name)
            : () => _downloadFile(l10n, file),
      ),
    );
  }

  void _showContextMenu(AppLocalizations l10n, Offset position, RemoteFile file) {
    final isDirectory = file.isDirectory;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              const Icon(Icons.download),
              const SizedBox(width: 8),
              Text(isDirectory ? l10n.downloadFolder : l10n.download),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, color: Colors.red),
              const SizedBox(width: 8),
              Text(l10n.delete, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleFileAction(l10n, value, file);
      }
    });
  }

  String _buildSubtitle(AppLocalizations l10n, RemoteFile file) {
    final parts = <String>[];
    if (file.isDirectory) {
      parts.add(l10n.folder);
    } else if (file.size != null) {
      parts.add(file.displaySize);
    }
    if (file.modifiedTime != null) {
      parts.add(_formatDateTime(l10n, file.modifiedTime!));
    }
    return parts.join(' • ');
  }

  String _formatDateTime(AppLocalizations l10n, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return l10n.todayTime('${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}');
    } else if (diff.inDays == 1) {
      return l10n.yesterday;
    } else if (diff.inDays < 7) {
      return l10n.daysAgo(diff.inDays);
    } else {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
  }

  IconData _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.ppt':
      case '.pptx':
        return Icons.slideshow;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
      case '.bmp':
        return Icons.image;
      case '.mp4':
      case '.avi':
      case '.mov':
      case '.mkv':
        return Icons.video_file;
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.aac':
        return Icons.audio_file;
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return Icons.folder_zip;
      case '.txt':
      case '.md':
        return Icons.text_snippet;
      case '.json':
      case '.xml':
      case '.yaml':
      case '.yml':
        return Icons.data_object;
      case '.dart':
      case '.js':
      case '.ts':
      case '.py':
      case '.java':
      case '.c':
      case '.cpp':
      case '.h':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _handleFileAction(AppLocalizations l10n, String action, RemoteFile file) {
    switch (action) {
      case 'download':
        if (file.isDirectory) {
          _downloadFolder(l10n, file);
        } else {
          _downloadFile(l10n, file);
        }
        break;
      case 'delete':
        _confirmDelete(l10n, file);
        break;
    }
  }

  Future<void> _pickAndUploadFiles() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      final files = result.files.where((f) => f.path != null).toList();
      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.couldNotAccessFiles),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Add files to the upload queue
      final filePaths = files.map((f) => f.path!).toList();
      await ref.read(uploadQueueProvider.notifier).addFiles(filePaths);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.addedFilesToQueue(files.length)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.error(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadFolder() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.selectFolderToUpload,
      );
      if (folderPath == null) return;

      final folderName = p.basename(folderPath);

      // Add folder to the upload queue
      await ref.read(uploadQueueProvider.notifier).addFolder(folderPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.addedFolderToQueue(folderName)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.error(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadFile(AppLocalizations l10n, RemoteFile file) async {
    try {
      // Use configured download location or system default
      String? downloadPath;

      if (_currentDownloadLocation != null) {
        // Ensure download directory exists
        final downloadDir = Directory(_currentDownloadLocation!);
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        downloadPath = p.join(_currentDownloadLocation!, file.name);
      } else if (Platform.isAndroid) {
        // Fallback for Android
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          downloadPath = p.join(dir.path, file.name);
        }
      } else {
        // Fallback to app documents directory
        final dir = await getApplicationDocumentsDirectory();
        downloadPath = p.join(dir.path, file.name);
      }

      if (downloadPath == null) return;

      // Get the current path to build the full remote path
      final fileListState = ref.read(fileListProvider);
      final remoteName = fileListState.currentPath.isEmpty
          ? file.name
          : '${fileListState.currentPath}/${file.name}';

      // Use the download provider
      final success = await ref.read(downloadStateProvider.notifier).downloadFile(
        remoteName: remoteName,
        localPath: downloadPath,
        fileSize: file.size,
      );

      if (mounted) {
        // Skip if state was cleared by user during download
        final dlState = ref.read(downloadStateProvider);
        if (dlState.items.isEmpty && !dlState.isDownloading) return;

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Expanded(child: Text(l10n.downloaded(file.name))),
                  GestureDetector(
                    onTap: _openDownloadLocation,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        l10n.openFolder,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              showCloseIcon: true,
            ),
          );
        } else {
          final dlState = ref.read(downloadStateProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(dlState.error ?? l10n.downloadFailed),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.error(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadFolder(AppLocalizations l10n, RemoteFile folder) async {
    final dlState = ref.read(downloadStateProvider);
    if (dlState.isDownloading) return;

    try {
      // Use configured download location or system default
      String? downloadBasePath;

      if (_currentDownloadLocation != null) {
        downloadBasePath = _currentDownloadLocation;
      } else if (Platform.isAndroid) {
        final dir = await getExternalStorageDirectory();
        downloadBasePath = dir?.path;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        downloadBasePath = dir.path;
      }

      if (downloadBasePath == null) return;

      // Ensure download directory exists
      final downloadDir = Directory(downloadBasePath);
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final localFolderPath = p.join(downloadBasePath, folder.name);

      // Get the current path to build the full remote path
      final fileListState = ref.read(fileListProvider);
      final remoteFolderName = fileListState.currentPath.isEmpty
          ? folder.name
          : '${fileListState.currentPath}/${folder.name}';

      // Use the download provider
      final downloadResult = await ref.read(downloadStateProvider.notifier).downloadFolder(
        remoteFolderName: remoteFolderName,
        localFolderPath: localFolderPath,
      );

      if (mounted) {
        if (downloadResult.isSuccess) {
          final count = downloadResult.data ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Expanded(child: Text(l10n.downloadedFolderWithCount(folder.name, count))),
                  GestureDetector(
                    onTap: _openDownloadLocation,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        l10n.openFolder,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              showCloseIcon: true,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(downloadResult.error?.userMessage ?? l10n.downloadFailed),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.error(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(AppLocalizations l10n, RemoteFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteFile),
        content: Text(l10n.deleteFileConfirm(file.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Get the current path to build the full remote path
      final fileListState = ref.read(fileListProvider);
      final remotePath = fileListState.currentPath.isEmpty
          ? file.name
          : '${fileListState.currentPath}/${file.name}';
      final success = await ref.read(fileListProvider.notifier).deleteFile(remotePath);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.deleted(file.name)),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.failedToDeleteFile),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
