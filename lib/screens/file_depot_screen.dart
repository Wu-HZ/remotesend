import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';
import '../providers/upload_queue_provider.dart';
import '../services/webdav_service.dart';
import 'upload_queue_screen.dart';

/// File Depot screen for uploading and downloading files via WebDAV.
class FileDepotScreen extends ConsumerStatefulWidget {
  const FileDepotScreen({super.key});

  @override
  ConsumerState<FileDepotScreen> createState() => _FileDepotScreenState();
}

class _FileDepotScreenState extends ConsumerState<FileDepotScreen> {
  // Download state (uploads are now handled by the queue provider)
  bool _isDownloading = false;
  String? _downloadingFileName;
  double _downloadProgress = 0;
  int _downloadingFileIndex = 0;
  int _downloadingFileTotal = 0;

  String? _currentDownloadLocation;

  @override
  void initState() {
    super.initState();
    // Refresh file list on screen load if connected
    Future.microtask(_initialLoad);
  }

  Future<void> _initialLoad() async {
    final connectionStatus = ref.read(connectionStatusProvider);
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

  Future<void> _openDownloadLocation() async {
    if (_currentDownloadLocation == null) return;

    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [_currentDownloadLocation!]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_currentDownloadLocation!]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [_currentDownloadLocation!]);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Open folder not supported on this platform')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open folder: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfigured = ref.watch(isConfiguredProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final fileListState = ref.watch(fileListProvider);
    final config = ref.watch(configProvider).valueOrNull;

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
    final canOperate = isConfigured && isConnected;

    return Scaffold(
      appBar: AppBar(
        leading: fileListState.isAtRoot
            ? null
            : IconButton(
                onPressed: () => ref.read(fileListProvider.notifier).navigateUp(),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Go back',
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('File Depot'),
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
        actions: [
          // Open download folder button
          if (_currentDownloadLocation != null)
            IconButton(
              onPressed: _openDownloadLocation,
              icon: const Icon(Icons.folder_open),
              tooltip: 'Open download folder',
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
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection warning banner
          if (!canOperate) _buildWarningBanner(isConfigured, isConnected),

          // Status indicator (always visible)
          _buildStatusIndicator(),

          // Error message
          if (fileListState.error != null) _buildErrorCard(fileListState.error!),

          // File list
          Expanded(
            child: _buildFileList(fileListState, canOperate),
          ),
        ],
      ),
      floatingActionButton: canOperate
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'folder',
                  onPressed: _pickAndUploadFolder,
                  icon: const Icon(Icons.folder),
                  label: const Text('Folder'),
                ),
                const SizedBox(width: 12),
                FloatingActionButton.extended(
                  heroTag: 'file',
                  onPressed: _pickAndUploadFiles,
                  icon: const Icon(Icons.insert_drive_file),
                  label: const Text('File'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildWarningBanner(bool isConfigured, bool isConnected) {
    String message;
    IconData icon;

    if (!isConfigured) {
      message = 'Configure WebDAV connection in Settings to use File Depot';
      icon = Icons.settings;
    } else if (!isConnected) {
      message = 'Not connected. Test connection in Settings';
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

  Widget _buildStatusIndicator() {
    final queueState = ref.watch(uploadQueueProvider);
    final isUploading = queueState.isProcessing;
    final isActive = isUploading || _isDownloading;

    // Determine status text and icon
    String statusText;
    IconData statusIcon;
    double progress;

    if (_isDownloading) {
      // Download takes priority in display
      final isFolderDownload = _downloadingFileTotal > 1;
      if (isFolderDownload) {
        statusText = 'Downloading: $_downloadingFileName ($_downloadingFileIndex/$_downloadingFileTotal)';
      } else {
        statusText = 'Downloading: $_downloadingFileName';
      }
      statusIcon = Icons.download;
      progress = _downloadProgress;
    } else if (isUploading) {
      final currentItem = queueState.currentItem;
      if (currentItem != null) {
        statusText = 'Uploading: ${currentItem.fileName} (${queueState.completedCount + 1}/${queueState.items.length})';
        progress = queueState.overallProgress;
      } else {
        statusText = 'Uploading...';
        progress = queueState.overallProgress;
      }
      statusIcon = Icons.upload;
    } else if (queueState.items.isNotEmpty) {
      statusText = '${queueState.completedCount}/${queueState.items.length} files uploaded';
      statusIcon = Icons.check_circle;
      progress = 1.0;
    } else {
      statusText = 'Idle';
      statusIcon = Icons.hourglass_empty;
      progress = 0;
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const UploadQueueScreen()),
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
                  if (isUploading && queueState.currentSpeed > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        queueState.displaySpeed,
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

  Widget _buildFileList(FileListState fileListState, bool canOperate) {
    if (!canOperate) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Connect to WebDAV to view files'),
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
              fileListState.isAtRoot ? 'No files yet' : 'Empty folder',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fileListState.isAtRoot
                  ? 'Tap the File or Folder button to upload'
                  : 'This folder is empty',
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
        itemCount: fileListState.files.length,
        itemBuilder: (context, index) {
          final file = fileListState.files[index];
          return _buildFileItem(file);
        },
      ),
    );
  }

  Widget _buildFileItem(RemoteFile file) {
    final isDirectory = file.isDirectory;

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition, file),
      child: ListTile(
        leading: Icon(
          isDirectory ? Icons.folder : _getFileIcon(file.name),
          color: isDirectory ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          file.name,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _buildSubtitle(file),
          style: TextStyle(
            color: Theme.of(context).colorScheme.outline,
            fontSize: 12,
          ),
        ),
        trailing: isDirectory
            ? const Icon(Icons.chevron_right)
            : PopupMenuButton<String>(
                onSelected: (value) => _handleFileAction(value, file),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(Icons.download),
                        SizedBox(width: 8),
                        Text('Download'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
        onTap: isDirectory
            ? () => ref.read(fileListProvider.notifier).navigateToFolder(file.name)
            : () => _downloadFile(file),
      ),
    );
  }

  void _showContextMenu(Offset position, RemoteFile file) {
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
              Text(isDirectory ? 'Download Folder' : 'Download'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleFileAction(value, file);
      }
    });
  }

  String _buildSubtitle(RemoteFile file) {
    final parts = <String>[];
    if (file.isDirectory) {
      parts.add('Folder');
    } else if (file.size != null) {
      parts.add(file.displaySize);
    }
    if (file.modifiedTime != null) {
      parts.add(_formatDateTime(file.modifiedTime!));
    }
    return parts.join(' • ');
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
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

  void _handleFileAction(String action, RemoteFile file) {
    switch (action) {
      case 'download':
        if (file.isDirectory) {
          _downloadFolder(file);
        } else {
          _downloadFile(file);
        }
        break;
      case 'delete':
        _confirmDelete(file);
        break;
    }
  }

  Future<void> _pickAndUploadFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      final files = result.files.where((f) => f.path != null).toList();
      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not access files'),
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
            content: Text('Added ${files.length} file(s) to upload queue'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadFolder() async {
    try {
      final folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select folder to upload',
      );
      if (folderPath == null) return;

      final folderName = p.basename(folderPath);

      // Add folder to the upload queue
      await ref.read(uploadQueueProvider.notifier).addFolder(folderPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added folder "$folderName" to upload queue'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadFile(RemoteFile file) async {
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

      setState(() {
        _isDownloading = true;
        _downloadingFileName = file.name;
        _downloadProgress = 0;
      });

      final webDavService = ref.read(webDavServiceProvider);
      final downloadResult = await webDavService.downloadFile(
        file.name,
        downloadPath,
        onProgress: (progress) {
          setState(() => _downloadProgress = progress);
        },
      );

      setState(() {
        _isDownloading = false;
        _downloadingFileName = null;
      });

      if (mounted) {
        if (downloadResult.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded: ${file.name}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Open folder',
                textColor: Colors.white,
                onPressed: _openDownloadLocation,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(downloadResult.error?.userMessage ?? 'Download failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadingFileName = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadFolder(RemoteFile folder) async {
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

      setState(() {
        _isDownloading = true;
        _downloadingFileName = folder.name;
        _downloadProgress = 0;
        _downloadingFileIndex = 0;
        _downloadingFileTotal = 0;
      });

      final webDavService = ref.read(webDavServiceProvider);
      final downloadResult = await webDavService.downloadFolder(
        remoteFolderName,
        localFolderPath,
        onProgress: (fileName, current, total, progress) {
          setState(() {
            _downloadingFileName = fileName;
            _downloadingFileIndex = current;
            _downloadingFileTotal = total;
            _downloadProgress = progress;
          });
        },
      );

      setState(() {
        _isDownloading = false;
        _downloadingFileName = null;
        _downloadingFileIndex = 0;
        _downloadingFileTotal = 0;
      });

      if (mounted) {
        if (downloadResult.isSuccess) {
          final count = downloadResult.data ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded folder "${folder.name}" ($count files)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Open folder',
                textColor: Colors.white,
                onPressed: _openDownloadLocation,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(downloadResult.error?.userMessage ?? 'Download failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadingFileName = null;
        _downloadingFileIndex = 0;
        _downloadingFileTotal = 0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(RemoteFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file.name}"?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(fileListProvider.notifier).deleteFile(file.name);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted: ${file.name}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete file'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
