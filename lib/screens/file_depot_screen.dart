import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../providers/config_provider.dart';
import '../providers/webdav_provider.dart';
import '../providers/upload_queue_provider.dart';
import '../providers/download_cache_provider.dart';
import '../providers/download_state_provider.dart';
import '../providers/pending_upload_provider.dart';
import '../providers/camera_capture_provider.dart';
import '../providers/download_path_provider.dart';
import '../services/webdav_service.dart';
import '../utils/date_time_utils.dart';
import '../widgets/server_list_panel.dart';
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
  final _scrollController = ScrollController();
  final Set<String> _selectedFileKeys = <String>{};
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

  String _remotePathForFile(RemoteFile file) {
    final currentPath = ref.read(fileListProvider).currentPath;
    return currentPath.isEmpty ? file.name : '$currentPath/${file.name}';
  }

  String _fileSelectionKey(RemoteFile file) => _remotePathForFile(file);

  List<RemoteFile> _itemsForMove(RemoteFile file) {
    final files = ref.read(fileListProvider).files;
    if (_isFileSelected(file)) {
      final selected = files.where(_isFileSelected).toList();
      if (selected.isNotEmpty) return selected;
    }
    return [file];
  }

  bool _isFileSelected(RemoteFile file) {
    return _selectedFileKeys.contains(_fileSelectionKey(file));
  }

  void _toggleFileSelection(RemoteFile file, bool selected) {
    final key = _fileSelectionKey(file);
    setState(() {
      if (selected) {
        _selectedFileKeys.add(key);
      } else {
        _selectedFileKeys.remove(key);
      }
    });
  }

  void _clearFileSelection() {
    if (_selectedFileKeys.isEmpty) return;
    setState(() => _selectedFileKeys.clear());
  }

  void _selectAllFiles(List<RemoteFile> files) {
    final keys = files.map(_fileSelectionKey).toSet();
    setState(() => _selectedFileKeys.addAll(keys));
  }

  Future<void> _openDownloadLocation({String? directory}) async {
    final l10n = AppLocalizations.of(context)!;
    final opener = ref.read(openLocalDirectoryProvider);
    try {
      if (directory == null) {
        final server = ref.read(activeFilesServerProvider);
        if (server == null) return;
        directory = await ref.read(downloadPathServiceProvider).serverDirectory(
          configuredDirectory: ref.read(configProvider).valueOrNull?.downloadLocation ?? '',
          server: server,
        );
      }
      if (!await opener(directory) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.openFileFolderNotSupported)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToOpenFolder(e.toString())),
            backgroundColor: Colors.red,
          ),
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
    final activeServer = ref.watch(activeFilesServerProvider);
    final servers = ref.watch(enabledServersProvider);
    final pendingFiles = ref.watch(pendingUploadProvider);
    final cameraSupported = ref.watch(cameraSupportedProvider);
    final cameraBusy = ref.watch(
      cameraCaptureProvider.select((state) => state.isBusy),
    );

    // Show pending upload page if there are files waiting
    if (pendingFiles.filePaths.isNotEmpty || pendingFiles.isSubmitting) {
      return _buildPendingUploadView(l10n);
    }

    final isConnected =
        connectionStatus.state == WebDavConnectionState.connected;
    final isConnecting =
        connectionStatus.state == WebDavConnectionState.connecting;
    final canOperate = isConfigured && (isConnected || isConnecting);

    ref.listen(filesConnectionStatusProvider, (prev, next) {
      if (prev?.state != WebDavConnectionState.connected &&
          next.state == WebDavConnectionState.connected) {
        ref.read(fileListProvider.notifier).refresh();
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final showServerList =
            servers.length > 1 && constraints.maxWidth >= 650;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            surfaceTintColor: Colors.transparent,
            title: Row(
              children: [
                if (canOperate)
                  StorageUsageWidget(
                    provider: filesStorageUsageProvider,
                    clearDescription: l10n.clearAllFiles(
                      activeServer?.name ?? '',
                    ),
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
                    if (_selectedFileKeys.isNotEmpty)
                      Text(
                        l10n.selectedItems(_selectedFileKeys.length),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
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
              if (_selectedFileKeys.isNotEmpty)
                IconButton(
                  onPressed: _clearFileSelection,
                  icon: const Icon(Icons.deselect),
                  tooltip: l10n.clearSelection,
                ),
              // Open download folder button
              if (activeServer != null)
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
              constraints: BoxConstraints(maxWidth: showServerList ? 846 : 630),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showServerList)
                    ServerListPanel(
                      l10n: l10n,
                      servers: servers,
                      activeServer: activeServer,
                      onServerSelected: _switchFilesServer,
                      onFileDropped: _uploadDroppedItemsToServer,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        // Connection warning banner
                        if (!canOperate)
                          _buildWarningBanner(
                            l10n,
                            isConfigured,
                            connectionStatus.state,
                          ),

                        // Status indicator (always visible)
                        _buildStatusIndicator(l10n),

                        // Error message
                        if (fileListState.error != null)
                          _buildErrorCard(fileListState.error!),

                        // File list
                        Expanded(
                          child: _buildFileList(
                            l10n,
                            fileListState,
                            canOperate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: canOperate || (cameraSupported && isConfigured)
              ? IgnorePointer(
                  ignoring: !_fabVisible || cameraBusy,
                  child: AnimatedSlide(
                    offset: _fabVisible ? Offset.zero : const Offset(0, 1.5),
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (cameraSupported && isConfigured) ...[
                          Tooltip(
                            message: l10n.takePhoto,
                            preferBelow: false,
                            verticalOffset: 36,
                            child: FloatingActionButton(
                              heroTag: 'camera',
                              tooltip: null,
                              onPressed: cameraBusy
                                  ? null
                                  : () => ref
                                        .read(cameraCaptureProvider.notifier)
                                        .capture(),
                              child: const Icon(Icons.camera_alt_outlined),
                            ),
                          ),
                          if (canOperate) const SizedBox(height: 12),
                        ],
                        if (canOperate)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: l10n.createFolder,
                                preferBelow: false,
                                verticalOffset: 36,
                                child: FloatingActionButton(
                                  heroTag: 'create-folder',
                                  tooltip: null,
                                  onPressed: () => _createFolder(l10n),
                                  child: const Icon(Icons.create_new_folder),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Tooltip(
                                message: l10n.folder,
                                preferBelow: false,
                                verticalOffset: 36,
                                child: FloatingActionButton(
                                  heroTag: 'folder',
                                  tooltip: null,
                                  onPressed: _pickAndUploadFolder,
                                  child: const Icon(Icons.folder),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Tooltip(
                                message: l10n.file,
                                preferBelow: false,
                                verticalOffset: 36,
                                child: FloatingActionButton(
                                  heroTag: 'file',
                                  tooltip: null,
                                  onPressed: _pickAndUploadFiles,
                                  child: const Icon(Icons.insert_drive_file),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Future<void> _switchFilesServer(ServerConfig server) async {
    if (server.id == ref.read(activeFilesServerProvider)?.id) return;

    await ref.read(configProvider.notifier).switchFilesServer(server.id);
    if (!mounted) return;
    await ref.read(filesConnectionStatusProvider.notifier).testConnection();
  }

  Widget _buildServerSelector(
    AppLocalizations l10n,
    ServerConfig? activeServer,
    List<ServerConfig> servers,
  ) {
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
              color: activeServer != null
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
      onSelected: (serverId) {
        final server = servers.firstWhere((server) => server.id == serverId);
        _switchFilesServer(server);
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
                    ? Text(
                        server.emoji,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      )
                    : Icon(
                        Icons.cloud,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
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
    return const PendingUploadScreen();
  }

  Widget _buildWarningBanner(
    AppLocalizations l10n,
    bool isConfigured,
    WebDavConnectionState connectionState,
  ) {
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
            child: Text(message, style: const TextStyle(color: Colors.orange)),
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
        statusText = l10n.downloadingFileWithProgress(
          downloadState.fileName ?? '',
          downloadState.currentFileIndex,
          downloadState.totalFiles,
        );
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
        statusText = l10n.uploadingFile(
          currentItem.fileName,
          queueState.completedCount + 1,
          queueState.items.length,
        );
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
        statusText =
            '${l10n.filesUploaded(queueState.completedCount, queueState.items.length)} ($fc failed)';
        statusIcon = Icons.warning_amber;
      } else {
        statusText = l10n.filesUploaded(
          queueState.completedCount,
          queueState.items.length,
        );
        statusIcon = Icons.check_circle;
      }
      progress = 1.0;
    } else if (downloadState.items.isNotEmpty && !downloadState.isDownloading) {
      final isFailed = downloadState.error != null;
      if (isFailed) {
        statusText = downloadState.error ?? l10n.downloadFailed;
        statusIcon = Icons.error;
      } else {
        statusText = l10n.filesDownloaded(
          downloadState.completedCount,
          downloadState.items.length,
        );
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
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
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

  Widget _buildFileList(
    AppLocalizations l10n,
    FileListState fileListState,
    bool canOperate,
  ) {
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

    if (fileListState.files.isEmpty && fileListState.isAtRoot) {
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
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    final downloadCache = ref.watch(downloadCacheProvider);
    final showClearSelection = _selectedFileKeys.length > 1;
    final selectionRowCount = showClearSelection ? 1 : 0;
    final parentRowCount = fileListState.isAtRoot ? 0 : 1;
    final contentRowCount = fileListState.files.isEmpty
        ? 1
        : fileListState.files.length;

    return RefreshIndicator(
      onRefresh: () => ref.read(fileListProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: selectionRowCount + parentRowCount + contentRowCount,
        itemBuilder: (context, index) {
          if (showClearSelection && index == 0) {
            return _buildSelectionActionsItem(l10n, fileListState);
          }

          final contentIndex = index - selectionRowCount;
          if (!fileListState.isAtRoot && contentIndex == 0) {
            return _buildParentDirectoryItem(l10n, fileListState);
          }
          if (fileListState.files.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  l10n.thisFolderIsEmpty,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            );
          }

          final fileIndex = fileListState.isAtRoot
              ? contentIndex
              : contentIndex - 1;
          final file = fileListState.files[fileIndex];
          return _buildFileItem(l10n, file, downloadCache);
        },
      ),
    );
  }

  Widget _buildSelectionActionsItem(
    AppLocalizations l10n,
    FileListState fileListState,
  ) {
    final allSelected =
        fileListState.files.isNotEmpty &&
        fileListState.files.every(_isFileSelected);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: allSelected
                  ? null
                  : () => _selectAllFiles(fileListState.files),
              icon: const Icon(Icons.select_all),
              label: Text(l10n.selectAll),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: _clearFileSelection,
              icon: const Icon(Icons.deselect),
              label: Text(l10n.clearSelection),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentDirectoryItem(
    AppLocalizations l10n,
    FileListState fileListState,
  ) {
    final parts = fileListState.currentPath.split('/');
    parts.removeLast();
    final parentPath = parts.join('/');
    final item = ListTile(
      leading: const Icon(Icons.subdirectory_arrow_left),
      title: const Text('..', style: TextStyle(fontWeight: FontWeight.bold)),
      onTap: () {
        _clearFileSelection();
        ref.read(fileListProvider.notifier).navigateUp();
      },
    );

    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return item;
    }

    return DragTarget<RemoteFile>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) =>
          _moveItemsToFolder(l10n, details.data, parentPath),
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: candidateData.isNotEmpty
              ? BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withAlpha(180),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: item,
        );
      },
    );
  }

  Widget _buildFileItem(
    AppLocalizations l10n,
    RemoteFile file,
    DownloadCacheState downloadCache,
  ) {
    final isDirectory = file.isDirectory;

    final item = GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(l10n, details.globalPosition, file),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: _isFileSelected(file),
              visualDensity: VisualDensity.compact,
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Theme.of(context).colorScheme.primary;
                }
                return Theme.of(context).colorScheme.surfaceContainerLow;
              }),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withAlpha(160),
              ),
              onChanged: (selected) =>
                  _toggleFileSelection(file, selected ?? false),
            ),
            Container(
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
                color: isDirectory
                    ? Theme.of(context).colorScheme.primary
                    : null,
                size: 22,
              ),
            ),
          ],
        ),
        title: Text(file.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          _buildSubtitle(l10n, file, downloadCache),
          style: TextStyle(
            color: Theme.of(context).colorScheme.outline,
            fontSize: 12,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleFileAction(l10n, value, file),
          itemBuilder: (context) => _buildFileMenuItems(l10n, file),
        ),
        onTap: isDirectory
            ? () {
                _clearFileSelection();
                ref.read(fileListProvider.notifier).navigateToFolder(file.name);
              }
            : () => _downloadFile(l10n, file),
      ),
    );

    // Internal drag-and-drop is intended for desktop; mobile keeps the menu
    // actions to avoid conflicting with scrolling gestures.
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return item;
    }

    final draggable = Draggable<RemoteFile>(
      data: file,
      feedback: _buildDragFeedback(l10n, file),
      childWhenDragging: Opacity(opacity: 0.35, child: item),
      child: item,
    );

    if (!isDirectory) return draggable;

    return DragTarget<RemoteFile>(
      onWillAcceptWithDetails: (details) =>
          !_itemsForMove(details.data).any((item) => item.name == file.name),
      onAcceptWithDetails: (details) =>
          _moveDraggedFileToFolder(l10n, details.data, file),
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: candidateData.isNotEmpty
              ? BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withAlpha(180),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: draggable,
        );
      },
    );
  }

  Widget _buildDragFeedback(AppLocalizations l10n, RemoteFile file) {
    final itemCount = _itemsForMove(file).length;
    final frontCard = _buildDragCard(
      l10n,
      file,
      itemCount: itemCount > 1 ? itemCount : null,
    );
    if (itemCount <= 1) return frontCard;

    // Stack cards behind the front card to make the selected batch look folded
    // together while it is being dragged.
    return SizedBox(
      width: 230,
      height: 68,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 10,
            top: 10,
            child: Opacity(opacity: 0.45, child: _buildDragCard(l10n, file)),
          ),
          Positioned(
            left: 5,
            top: 5,
            child: Opacity(opacity: 0.7, child: _buildDragCard(l10n, file)),
          ),
          frontCard,
        ],
      ),
    );
  }

  Widget _buildDragCard(
    AppLocalizations l10n,
    RemoteFile file, {
    int? itemCount,
  }) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SizedBox(
        width: 220,
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                file.isDirectory ? Icons.folder : _getFileIcon(file.name),
                color: file.isDirectory
                    ? Theme.of(context).colorScheme.primary
                    : null,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (itemCount != null) ...[
                const SizedBox(width: 4),
                Text(
                  l10n.draggingItemsSuffix(itemCount),
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _moveItemsToFolder(
    AppLocalizations l10n,
    RemoteFile source,
    String destinationPath,
  ) async {
    final items = _itemsForMove(source);
    final sourcePaths = items.map(_remotePathForFile).toList();
    final directoryPaths = items
        .where((item) => item.isDirectory)
        .map(_remotePathForFile)
        .toSet();

    // Do not move a folder into itself or one of its descendants.
    if (items.any((item) {
      final sourcePath = _remotePathForFile(item);
      return item.isDirectory &&
          (destinationPath == sourcePath ||
              destinationPath.startsWith('$sourcePath/'));
    })) {
      return;
    }

    final success = await ref
        .read(fileListProvider.notifier)
        .moveFiles(
          sourcePaths,
          destinationPath,
          directoryPaths: directoryPaths,
        );
    if (mounted) {
      if (success) {
        setState(() => _selectedFileKeys.removeAll(sourcePaths));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success && items.length > 1
                ? l10n.movedItems(items.length)
                : success
                ? l10n.moved(source.name)
                : l10n.failedToMoveFile,
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _moveDraggedFileToFolder(
    AppLocalizations l10n,
    RemoteFile source,
    RemoteFile destination,
  ) async {
    final currentPath = ref.read(fileListProvider).currentPath;
    final destinationPath = currentPath.isEmpty
        ? destination.name
        : '$currentPath/${destination.name}';
    await _moveItemsToFolder(l10n, source, destinationPath);
  }

  List<PopupMenuEntry<String>> _buildFileMenuItems(
    AppLocalizations l10n,
    RemoteFile file,
  ) {
    final activeServerId = ref.read(activeFilesServerProvider)?.id;
    final hasOtherServer = ref
        .read(enabledServersProvider)
        .any((server) => server.id != activeServerId);

    return [
      PopupMenuItem(
        value: 'download',
        child: Row(
          children: [
            const Icon(Icons.download),
            const SizedBox(width: 8),
            Text(file.isDirectory ? l10n.downloadFolder : l10n.download),
          ],
        ),
      ),
      if (hasOtherServer)
        PopupMenuItem(
          value: 'uploadToServer',
          child: Row(
            children: [
              const Icon(Icons.cloud_upload),
              const SizedBox(width: 8),
              Text(l10n.uploadToServer),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'rename',
        child: Row(
          children: [
            const Icon(Icons.drive_file_rename_outline),
            const SizedBox(width: 8),
            Text(l10n.rename),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'move',
        child: Row(
          children: [
            const Icon(Icons.drive_file_move),
            const SizedBox(width: 8),
            Text(l10n.moveToFolder),
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
    ];
  }

  void _showContextMenu(
    AppLocalizations l10n,
    Offset position,
    RemoteFile file,
  ) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: _buildFileMenuItems(l10n, file),
    ).then((value) {
      if (value != null) {
        _handleFileAction(l10n, value, file);
      }
    });
  }

  String _buildSubtitle(
    AppLocalizations l10n,
    RemoteFile file,
    DownloadCacheState downloadCache,
  ) {
    final parts = <String>[];
    if (file.isDirectory) {
      parts.add(l10n.folder);
    } else if (file.size != null) {
      parts.add(file.displaySize);
    }
    if (file.modifiedTime != null) {
      parts.add(_formatDateTime(l10n, file.modifiedTime!));
    }

    final serverId = ref.read(activeFilesServerProvider)?.id;
    if (serverId != null &&
        downloadCache.isDownloaded(serverId: serverId, file: file)) {
      parts.add(l10n.downloadedStatus);
    }
    return parts.join(' • ');
  }

  String _formatDateTime(AppLocalizations l10n, DateTime dt) {
    final localTime = dt.toLocal();
    final dayDifference = localCalendarDayDifference(DateTime.now(), localTime);
    final time =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';

    if (dayDifference == 0) {
      return l10n.todayTime(time);
    } else if (dayDifference == 1) {
      return l10n.yesterdayTime(time);
    } else if (dayDifference > 1 && dayDifference < 7) {
      return l10n.daysAgo(dayDifference);
    } else {
      return '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')}';
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

  void _handleFileAction(
    AppLocalizations l10n,
    String action,
    RemoteFile file,
  ) {
    switch (action) {
      case 'download':
        if (file.isDirectory) {
          _downloadFolder(l10n, file);
        } else {
          _downloadFile(l10n, file);
        }
        break;
      case 'uploadToServer':
        _prepareItemsForPendingUpload(l10n, file);
        break;
      case 'rename':
        _renameFile(l10n, file);
        break;
      case 'move':
        _moveToFolder(l10n, file);
        break;
      case 'delete':
        _confirmDelete(l10n, file);
        break;
    }
  }

  Future<void> _prepareItemsForPendingUpload(
    AppLocalizations l10n,
    RemoteFile source,
  ) async {
    final sourceServer = ref.read(activeFilesServerProvider);
    if (sourceServer == null) return;
    final root = ref.read(configProvider).valueOrNull?.downloadLocation ?? '';
    final currentPath = ref.read(fileListProvider).currentPath;
    final paths = <String>[];
    for (final item in _itemsForMove(source)) {
      final localPath = await _ensureLocalCopy(l10n, item,
        server: sourceServer, configuredDirectory: root, currentPath: currentPath);
      if (localPath != null) paths.add(localPath);
    }
    if (!mounted) return;

    if (paths.isNotEmpty) {
      ref.read(pendingUploadProvider.notifier).addFiles(paths);
    }
  }

  Future<void> _uploadDroppedItemsToServer(
    ServerConfig target,
    RemoteFile source,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final sourceServer = ref.read(activeFilesServerProvider);
    if (sourceServer == null) return;
    final root = ref.read(configProvider).valueOrNull?.downloadLocation ?? '';
    final currentPath = ref.read(fileListProvider).currentPath;
    final paths = <String>[];
    for (final item in _itemsForMove(source)) {
      final localPath = await _ensureLocalCopy(l10n, item,
        server: sourceServer, configuredDirectory: root, currentPath: currentPath);
      if (localPath != null) paths.add(localPath);
    }
    if (!mounted) return;
    if (paths.isEmpty) return;

    // Reuse the normal upload queue so the target upload has the same
    // progress display, retry behavior, and completion handling.
    await _switchFilesServer(target);
    await _enqueueLocalPathsForUpload(paths);
  }

  Future<void> _enqueueLocalPathsForUpload(List<String> paths) async {
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

    for (final folder in folders) {
      await ref.read(uploadQueueProvider.notifier).addFolder(folder);
    }
    if (files.isNotEmpty) {
      await ref.read(uploadQueueProvider.notifier).addFiles(files);
    }
  }

  Future<String?> _ensureLocalCopy(
    AppLocalizations l10n,
    RemoteFile file, {
    required ServerConfig server,
    required String configuredDirectory,
    required String currentPath,
  }) async {
    await ref.read(downloadCacheProvider.notifier).ready;
    if (!mounted) return null;
    final cache = ref.read(downloadCacheProvider);
    final cachedPath = cache.localPathFor(serverId: server.id, file: file);
    if (cachedPath != null) return cachedPath;
    final remoteName = currentPath.isEmpty ? file.name : '$currentPath/${file.name}';

    if (file.isDirectory) {
      await _downloadFolder(l10n, file, sourceServer: server,
        configuredDirectory: configuredDirectory, sourceRemoteName: remoteName);
    } else {
      await _downloadFile(l10n, file, sourceServer: server,
        configuredDirectory: configuredDirectory, sourceRemoteName: remoteName);
    }
    if (!mounted) return null;
    return ref
        .read(downloadCacheProvider)
        .localPathFor(serverId: server.id, file: file);
  }

  Future<void> _moveToFolder(AppLocalizations l10n, RemoteFile file) async {
    final fileListState = ref.read(fileListProvider);
    final items = _itemsForMove(file);
    final excludedPaths = items
        .where((item) => item.isDirectory)
        .map(_remotePathForFile)
        .toList();
    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => _FolderPickerDialog(
        l10n: l10n,
        service: ref.read(webDavFilesServiceProvider),
        currentParentPath: fileListState.currentPath,
        excludedPaths: excludedPaths,
      ),
    );

    if (destinationPath == null ||
        destinationPath == fileListState.currentPath) {
      return;
    }

    await _moveItemsToFolder(l10n, file, destinationPath);
  }

  Future<void> _createFolder(AppLocalizations l10n) async {
    final controller = TextEditingController();
    try {
      final folderName = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          String? validationError;

          return StatefulBuilder(
            builder: (context, setState) {
              void submit() {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setState(() => validationError = l10n.folderNameRequired);
                  return;
                }
                if (value == '.' ||
                    value == '..' ||
                    value.contains('/') ||
                    value.contains('\\')) {
                  setState(() => validationError = l10n.folderNameInvalid);
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              }

              return AlertDialog(
                title: Text(l10n.createFolder),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: l10n.folderNameHint,
                    errorText: validationError,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: submit,
                    child: Text(l10n.createFolder),
                  ),
                ],
              );
            },
          );
        },
      );

      if (folderName == null) return;

      final success = await ref
          .read(fileListProvider.notifier)
          .createFolder(folderName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? l10n.folderCreated(folderName)
                  : l10n.failedToCreateFolder,
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      controller.dispose();
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

  void _showAlreadyDownloaded(AppLocalizations l10n, RemoteFile file, String localPath) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.alreadyDownloaded(file.name)),
        action: SnackBarAction(
          label: l10n.openFolder,
          onPressed: () => _openDownloadLocation(
            directory: file.isDirectory ? localPath : p.dirname(localPath),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadFile(AppLocalizations l10n, RemoteFile file, {
    ServerConfig? sourceServer,
    String? configuredDirectory,
    String? sourceRemoteName,
  }) async {
    try {
      final fileListState = ref.read(fileListProvider);
      final remoteName = sourceRemoteName ?? (fileListState.currentPath.isEmpty
          ? file.name
          : '${fileListState.currentPath}/${file.name}');
      final server = sourceServer ?? ref.read(activeFilesServerProvider);
      if (server == null) return;
      final root = configuredDirectory ?? ref.read(configProvider).valueOrNull?.downloadLocation ?? '';
      final paths = ref.read(downloadPathServiceProvider);
      final service = ref.read(downloadSourceServiceProvider)(server);

      await ref.read(downloadCacheProvider.notifier).ready;
      if (!mounted) return;
      final cachedPath = ref.read(downloadCacheProvider).localPathFor(serverId: server.id, file: file);
      if (cachedPath != null) {
        _showAlreadyDownloaded(l10n, file, cachedPath);
        return;
      }
      final downloadPath = await paths.downloadPath(
        configuredDirectory: root,
        server: server,
        fileName: file.name,
      );
      if (!mounted) return;

      // Use the download provider
      final success = await ref
          .read(downloadStateProvider.notifier)
          .downloadFile(
            remoteName: remoteName,
            localPath: downloadPath,
            fileSize: file.size,
            serviceOverride: service,
          );
      if (!mounted) return;

      if (success) {
        await ref
            .read(downloadCacheProvider.notifier)
            .markDownloaded(
              serverId: server.id,
              file: file,
              localPath: downloadPath,
            );
      }

      if (mounted) {
        // Skip if state was cleared by user during download
        final dlState = ref.read(downloadStateProvider);
        if (dlState.items.isEmpty && !dlState.isDownloading) return;

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Expanded(
                    child: Text(l10n.downloaded(p.basename(downloadPath))),
                  ),
                  GestureDetector(
                    onTap: () => _openDownloadLocation(directory: p.dirname(downloadPath)),
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

  Future<void> _downloadFolder(AppLocalizations l10n, RemoteFile folder, {
    ServerConfig? sourceServer,
    String? configuredDirectory,
    String? sourceRemoteName,
  }) async {
    final dlState = ref.read(downloadStateProvider);
    if (dlState.isDownloading) return;

    final fileListState = ref.read(fileListProvider);
    final server = sourceServer ?? ref.read(activeFilesServerProvider);
    if (server == null) return;
    final root = configuredDirectory ?? ref.read(configProvider).valueOrNull?.downloadLocation ?? '';
    final remoteFolderName = sourceRemoteName ?? (fileListState.currentPath.isEmpty
        ? folder.name
        : '${fileListState.currentPath}/${folder.name}');
    final paths = ref.read(downloadPathServiceProvider);
    final service = ref.read(downloadSourceServiceProvider)(server);

    try {
      await ref.read(downloadCacheProvider.notifier).ready;
      if (!mounted) return;
      final cachedPath = ref.read(downloadCacheProvider).localPathFor(serverId: server.id, file: folder);
      if (cachedPath != null) {
        _showAlreadyDownloaded(l10n, folder, cachedPath);
        return;
      }
      final localFolderPath = await paths.downloadPath(
        configuredDirectory: root,
        server: server,
        fileName: folder.name,
        isDirectory: true,
      );
      if (!mounted) return;

      // Use the download provider
      final downloadResult = await ref
          .read(downloadStateProvider.notifier)
          .downloadFolder(
            remoteFolderName: remoteFolderName,
            localFolderPath: localFolderPath,
            serviceOverride: service,
          );
      if (!mounted) return;

      if (downloadResult.isSuccess) {
        await ref
            .read(downloadCacheProvider.notifier)
            .markDownloaded(
              serverId: server.id,
              file: folder,
              localPath: localFolderPath,
            );
      }

      if (mounted) {
        if (downloadResult.isSuccess) {
          final count = downloadResult.data ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.downloadedFolderWithCount(folder.name, count),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _openDownloadLocation(directory: localFolderPath),
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
              content: Text(
                downloadResult.error?.userMessage ?? l10n.downloadFailed,
              ),
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

  Future<void> _renameFile(AppLocalizations l10n, RemoteFile file) async {
    final controller = TextEditingController(text: file.name);
    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          String? validationError;

          return StatefulBuilder(
            builder: (context, setState) {
              void submit() {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setState(() => validationError = l10n.renameFileNameRequired);
                  return;
                }
                if (value == '.' ||
                    value == '..' ||
                    value.contains('/') ||
                    value.contains('\\')) {
                  setState(() => validationError = l10n.renameFileNameInvalid);
                  return;
                }
                Navigator.of(
                  dialogContext,
                ).pop(value == file.name ? null : value);
              }

              return AlertDialog(
                title: Text(l10n.renameFile),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: l10n.renameFileHint,
                    errorText: validationError,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(onPressed: submit, child: Text(l10n.rename)),
                ],
              );
            },
          );
        },
      );

      if (newName == null) return;

      final fileListState = ref.read(fileListProvider);
      final remotePath = fileListState.currentPath.isEmpty
          ? file.name
          : '${fileListState.currentPath}/${file.name}';
      final success = await ref
          .read(fileListProvider.notifier)
          .renameFile(remotePath, newName, isDirectory: file.isDirectory);

      if (mounted) {
        if (success) {
          setState(() => _selectedFileKeys.remove(remotePath));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? l10n.renamed(newName) : l10n.failedToRenameFile,
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      controller.dispose();
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      final success = await ref
          .read(fileListProvider.notifier)
          .deleteFile(remotePath);

      if (mounted) {
        if (success) {
          setState(() => _selectedFileKeys.remove(remotePath));
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

class _FolderPickerDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final WebDavService service;
  final String currentParentPath;
  final List<String> excludedPaths;

  const _FolderPickerDialog({
    required this.l10n,
    required this.service,
    required this.currentParentPath,
    this.excludedPaths = const [],
  });

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  String _currentPath = '';
  List<RemoteFile> _folders = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await widget.service.listFiles(
      _currentPath.isEmpty ? null : _currentPath,
    );
    if (!mounted) return;

    if (result.isSuccess) {
      final folders = (result.data ?? [])
          .where((file) => file.isDirectory)
          .where((folder) => !_isExcluded(_folderPath(folder.name)))
          .toList();
      setState(() {
        _folders = folders;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _error = result.error?.userMessage;
      });
    }
  }

  String _folderPath(String folderName) {
    return _currentPath.isEmpty ? folderName : '$_currentPath/$folderName';
  }

  bool _isExcluded(String path) {
    return widget.excludedPaths.any(
      (excludedPath) =>
          path == excludedPath || path.startsWith('$excludedPath/'),
    );
  }

  Future<void> _enterFolder(String folderName) async {
    setState(() => _currentPath = _folderPath(folderName));
    await _loadFolders();
  }

  Future<void> _navigateUp() async {
    final parts = _currentPath.split('/');
    parts.removeLast();
    setState(() => _currentPath = parts.join('/'));
    await _loadFolders();
  }

  Widget _buildFolderContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadFolders, child: Text(widget.l10n.retry)),
          ],
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(child: Text(widget.l10n.noSubfolders));
    }

    return ListView.builder(
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        final folderPath = _folderPath(folder.name);
        return ListTile(
          leading: const Icon(Icons.folder),
          title: Text(folder.name),
          trailing: IconButton(
            tooltip: widget.l10n.moveHere,
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(folderPath),
          ),
          onTap: () => _enterFolder(folder.name),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canMoveHere = _currentPath != widget.currentParentPath;
    return AlertDialog(
      title: Text(widget.l10n.moveToFolder),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: widget.l10n.goBack,
                  onPressed: _currentPath.isEmpty ? null : _navigateUp,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    _currentPath.isEmpty ? widget.l10n.filesRoot : _currentPath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(child: _buildFolderContent()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.cancel),
        ),
        FilledButton(
          onPressed: canMoveHere
              ? () => Navigator.of(context).pop(_currentPath)
              : null,
          child: Text(widget.l10n.moveHere),
        ),
      ],
    );
  }
}
