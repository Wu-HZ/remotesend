import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/server_config.dart';
import '../services/webdav_service.dart';
import '../services/webdav_exceptions.dart';
import 'config_provider.dart';

/// Provider for the WebDavService for Text Bridge.
final webDavTextServiceProvider = Provider<WebDavService>((ref) {
  final service = WebDavService();

  // Watch config changes and reinitialize service when text server changes
  ref.listen<ServerConfig?>(activeTextServerProvider, (previous, next) {
    if (next != null && next.isConfigured) {
      service.initializeWithServer(next);
    } else {
      service.disconnect();
    }
  });

  // Initialize with current server if available
  final currentServer = ref.read(activeTextServerProvider);
  if (currentServer != null && currentServer.isConfigured) {
    service.initializeWithServer(currentServer);
  }

  return service;
});

/// Provider for the WebDavService for File Depot.
final webDavFilesServiceProvider = Provider<WebDavService>((ref) {
  final service = WebDavService();

  // Watch config changes and reinitialize service when files server changes
  ref.listen<ServerConfig?>(activeFilesServerProvider, (previous, next) {
    if (next != null && next.isConfigured) {
      service.initializeWithServer(next);
    } else {
      service.disconnect();
    }
  });

  // Initialize with current server if available
  final currentServer = ref.read(activeFilesServerProvider);
  if (currentServer != null && currentServer.isConfigured) {
    service.initializeWithServer(currentServer);
  }

  return service;
});

/// Backward-compatible provider (uses text service).
final webDavServiceProvider = Provider<WebDavService>((ref) {
  return ref.watch(webDavTextServiceProvider);
});

/// Connection state for the WebDAV service.
enum WebDavConnectionState { disconnected, connecting, connected, error }

/// State class for connection status.
class ConnectionStatus {
  final WebDavConnectionState state;
  final String? errorMessage;
  final DateTime? lastChecked;

  const ConnectionStatus({
    required this.state,
    this.errorMessage,
    this.lastChecked,
  });

  const ConnectionStatus.disconnected()
    : state = WebDavConnectionState.disconnected,
      errorMessage = null,
      lastChecked = null;

  ConnectionStatus copyWith({
    WebDavConnectionState? state,
    String? errorMessage,
    DateTime? lastChecked,
  }) {
    return ConnectionStatus(
      state: state ?? this.state,
      errorMessage: errorMessage,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

/// Notifier for managing connection status.
class ConnectionNotifier extends StateNotifier<ConnectionStatus> {
  final WebDavService _service;
  int _generation = 0;

  ConnectionNotifier(this._service)
    : super(const ConnectionStatus.disconnected());

  /// Test the connection and update status. Startup retries transient failures
  /// without replacing a newer connection attempt or a server switch.
  Future<bool> testConnection({
    int maxAttempts = 1,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
    final generation = ++_generation;
    state = ConnectionStatus(
      state: WebDavConnectionState.connecting,
      lastChecked: state.lastChecked,
    );

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = await _service.testConnection();
      if (!mounted || generation != _generation) return false;

      if (result.isSuccess) {
        state = ConnectionStatus(
          state: WebDavConnectionState.connected,
          lastChecked: DateTime.now(),
        );
        return true;
      }
      final error = result.error;
      final transient = error is WebDavConnectionException ||
          error is WebDavTimeoutException ||
          error is WebDavServerException ||
          error is WebDavUnknownException;
      if (attempt < maxAttempts && transient) {
        await Future<void>.delayed(retryDelay);
        if (!mounted || generation != _generation) return false;
        continue;
      }
      state = ConnectionStatus(
        state: WebDavConnectionState.error,
        errorMessage: error?.userMessage,
        lastChecked: DateTime.now(),
      );
      return false;
    }
    return false;
  }

  /// Initialize the RemoteSend folder structure on the server.
  Future<WebDavResult<bool>> initializeFolderStructure() async {
    return _service.ensureFolderStructure();
  }

  /// Reset connection status.
  void reset() {
    ++_generation;
    state = const ConnectionStatus.disconnected();
  }
}

/// Provider for connection status management for Text Bridge.
final textConnectionStatusProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionStatus>((ref) {
      final service = ref.watch(webDavTextServiceProvider);
      final notifier = ConnectionNotifier(service);
      ref.listen<ServerConfig?>(activeTextServerProvider, (previous, next) {
        if (previous?.id != next?.id) notifier.reset();
      });
      return notifier;
    });

/// Provider for connection status management for File Depot.
final filesConnectionStatusProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionStatus>((ref) {
      final service = ref.watch(webDavFilesServiceProvider);
      final notifier = ConnectionNotifier(service);
      ref.listen<ServerConfig?>(activeFilesServerProvider, (previous, next) {
        if (previous?.id != next?.id) notifier.reset();
      });
      return notifier;
    });

/// Backward-compatible provider (uses text connection status).
final connectionStatusProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionStatus>((ref) {
      final service = ref.watch(webDavTextServiceProvider);
      return ConnectionNotifier(service);
    });

/// Provider for checking if text service is ready to use.
final isTextServiceReadyProvider = Provider<bool>((ref) {
  final isConfigured = ref.watch(isTextConfiguredProvider);
  final connectionStatus = ref.watch(textConnectionStatusProvider);
  return isConfigured &&
      connectionStatus.state == WebDavConnectionState.connected;
});

/// Provider for checking if files service is ready to use.
final isFilesServiceReadyProvider = Provider<bool>((ref) {
  final isConfigured = ref.watch(isFilesConfiguredProvider);
  final connectionStatus = ref.watch(filesConnectionStatusProvider);
  return isConfigured &&
      connectionStatus.state == WebDavConnectionState.connected;
});

/// Backward-compatible provider (checks text service).
final isServiceReadyProvider = Provider<bool>((ref) {
  return ref.watch(isTextServiceReadyProvider);
});

/// State for the text buffer.
class BufferState {
  final String content;
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final DateTime? lastSync;

  const BufferState({
    this.content = '',
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.lastSync,
  });

  BufferState copyWith({
    String? content,
    bool? isLoading,
    bool? isSaving,
    String? error,
    DateTime? lastSync,
  }) {
    return BufferState(
      content: content ?? this.content,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

/// Notifier for managing the text buffer.
class BufferNotifier extends StateNotifier<BufferState> {
  final WebDavService _service;

  BufferNotifier(this._service) : super(const BufferState());

  /// Pull content from the remote buffer.
  Future<bool> pullFromRemote() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _service.readBuffer();

    if (result.isSuccess) {
      state = BufferState(content: result.data ?? '', lastSync: DateTime.now());
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error?.userMessage,
      );
      return false;
    }
  }

  /// Push content to the remote buffer.
  Future<bool> pushToRemote(String content) async {
    state = state.copyWith(isSaving: true, error: null);

    final result = await _service.writeBuffer(content);

    if (result.isSuccess) {
      state = BufferState(content: content, lastSync: DateTime.now());
      return true;
    } else {
      state = state.copyWith(isSaving: false, error: result.error?.userMessage);
      return false;
    }
  }

  /// Update local content without syncing.
  void updateLocalContent(String content) {
    state = state.copyWith(content: content);
  }

  /// Clear the buffer.
  void clear() {
    state = const BufferState();
  }
}

/// Provider for buffer state management.
final bufferProvider = StateNotifierProvider<BufferNotifier, BufferState>((
  ref,
) {
  final service = ref.watch(webDavServiceProvider);
  return BufferNotifier(service);
});

/// State for the file list.
class FileListState {
  final List<RemoteFile> files;
  final bool isLoading;
  final String? error;
  final DateTime? lastRefresh;
  final String
  currentPath; // Current path relative to Files folder (empty = root)

  const FileListState({
    this.files = const [],
    this.isLoading = false,
    this.error,
    this.lastRefresh,
    this.currentPath = '',
  });

  /// Check if we're at the root of Files folder
  bool get isAtRoot => currentPath.isEmpty;

  /// Get the display name for current path
  String get currentPathDisplay => currentPath.isEmpty ? 'Files' : currentPath;

  FileListState copyWith({
    List<RemoteFile>? files,
    bool? isLoading,
    String? error,
    DateTime? lastRefresh,
    String? currentPath,
  }) {
    return FileListState(
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastRefresh: lastRefresh ?? this.lastRefresh,
      currentPath: currentPath ?? this.currentPath,
    );
  }
}

/// Notifier for managing the file list.
class FileListNotifier extends StateNotifier<FileListState> {
  final WebDavService _service;
  int _generation = 0;

  FileListNotifier(this._service) : super(const FileListState());

  /// Refresh the file list from the server. A transient network failure gets
  /// one retry; a newer refresh or server switch cancels the old result.
  Future<bool> refresh({
    bool retryTransient = true,
    Duration retryDelay = const Duration(seconds: 1),
  }) async {
    final generation = ++_generation;
    final path = state.currentPath;
    state = state.copyWith(isLoading: true, error: null);

    for (var attempt = 0; attempt < (retryTransient ? 2 : 1); attempt++) {
      final result = await _service.listFiles(path);
      if (!mounted || generation != _generation) return false;

      if (result.isSuccess) {
        state = state.copyWith(
          files: result.data ?? [],
          isLoading: false,
          lastRefresh: DateTime.now(),
        );
        return true;
      }
      final error = result.error;
      final transient = error is WebDavConnectionException ||
          error is WebDavTimeoutException ||
          error is WebDavServerException ||
          error is WebDavUnknownException;
      if (attempt == 0 && retryTransient && transient) {
        await Future<void>.delayed(retryDelay);
        if (!mounted || generation != _generation) return false;
        continue;
      }
      state = state.copyWith(isLoading: false, error: error?.userMessage);
      return false;
    }
    return false;
  }

  /// Navigate into a folder.
  Future<bool> navigateToFolder(String folderName) async {
    final previousPath = state.currentPath;
    final newPath = previousPath.isEmpty
        ? folderName
        : '$previousPath/$folderName';

    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null, currentPath: newPath);

    final result = await _service.listFiles(newPath);
    if (!mounted || generation != _generation) return false;

    if (result.isSuccess) {
      state = state.copyWith(
        files: result.data ?? [],
        isLoading: false,
        lastRefresh: DateTime.now(),
      );
      return true;
    } else {
      // Revert to previous path on error
      state = state.copyWith(
        isLoading: false,
        error: result.error?.userMessage,
        currentPath: previousPath,
      );
      return false;
    }
  }

  /// Navigate up one level.
  Future<bool> navigateUp() async {
    if (state.isAtRoot) return true;

    final parts = state.currentPath.split('/');
    parts.removeLast();
    final newPath = parts.join('/');

    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null, currentPath: newPath);

    final result = await _service.listFiles(newPath.isEmpty ? null : newPath);
    if (!mounted || generation != _generation) return false;

    if (result.isSuccess) {
      state = state.copyWith(
        files: result.data ?? [],
        isLoading: false,
        lastRefresh: DateTime.now(),
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error?.userMessage,
      );
      return false;
    }
  }

  /// Navigate to root.
  Future<bool> navigateToRoot() async {
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null, currentPath: '');

    final result = await _service.listFiles();
    if (!mounted || generation != _generation) return false;

    if (result.isSuccess) {
      state = state.copyWith(
        files: result.data ?? [],
        isLoading: false,
        lastRefresh: DateTime.now(),
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error?.userMessage,
      );
      return false;
    }
  }

  /// Delete a file from the server.
  Future<bool> deleteFile(String filePath) async {
    final generation = _generation;
    final result = await _service.deleteFile(filePath);
    if (!mounted || generation != _generation) return false;

    if (result.isSuccess) {
      // Remove from local list - extract file name from path for comparison
      final fileName = p.basename(filePath);
      state = state.copyWith(
        files: state.files.where((f) => f.name != fileName).toList(),
      );
      return true;
    }
    return false;
  }

  /// Move one or more files or folders into another folder.
  Future<bool> moveFiles(
    List<String> filePaths,
    String destinationPath, {
    Set<String> directoryPaths = const <String>{},
  }) async {
    final generation = _generation;
    var success = true;
    for (final filePath in filePaths) {
      if (!mounted || generation != _generation) return false;
      final result = await _service.moveFile(
        filePath,
        destinationPath,
        isDirectory: directoryPaths.contains(filePath),
      );
      if (!mounted || generation != _generation) return false;
      if (result.isFailure) {
        success = false;
        break;
      }
    }

    // Refresh even after a partial failure so the local list reflects moves
    // that were already accepted by the server.
    await refresh();
    return success;
  }

  /// Move a file or folder into another folder.
  Future<bool> moveFile(
    String filePath,
    String destinationPath, {
    bool isDirectory = false,
  }) {
    return moveFiles(
      [filePath],
      destinationPath,
      directoryPaths: isDirectory ? {filePath} : const <String>{},
    );
  }

  /// Create a folder in the current directory.
  Future<bool> createFolder(String folderName) async {
    final generation = _generation;
    final remotePath = state.currentPath.isEmpty
        ? folderName
        : '${state.currentPath}/$folderName';
    final result = await _service.createRemoteDirectory(
      '${_service.filesFolderPath}/$remotePath',
    );
    if (!mounted || generation != _generation) return false;

    if (result.isSuccess) {
      // Refresh so the new folder appears with the server-provided metadata.
      await refresh();
      return true;
    }
    return false;
  }

  /// Rename a file or folder in the current directory.
  Future<bool> renameFile(
    String filePath,
    String newName, {
    bool isDirectory = false,
  }) async {
    final generation = _generation;
    final result = await _service.renameFile(
      filePath,
      newName,
      isDirectory: isDirectory,
    );
    if (!mounted || generation != _generation) return false;

    if (result.isSuccess) {
      final oldName = filePath.split('/').last;
      state = state.copyWith(
        files: state.files.map((file) {
          if (file.name != oldName) return file;
          return RemoteFile(
            name: newName,
            path: file.path,
            size: file.size,
            modifiedTime: file.modifiedTime,
            isDirectory: file.isDirectory,
          );
        }).toList(),
      );
      return true;
    }
    return false;
  }

  /// Clear the file list.
  void clear() {
    ++_generation;
    state = const FileListState();
  }
}

/// Provider for file list state management (uses Files service).
final fileListProvider = StateNotifierProvider<FileListNotifier, FileListState>(
  (ref) {
    final service = ref.watch(webDavFilesServiceProvider);
    final notifier = FileListNotifier(service);
    ref.listen<ServerConfig?>(activeFilesServerProvider, (previous, next) {
      if (previous?.id != next?.id) notifier.clear();
    });
    return notifier;
  },
);

/// State for storage usage.
class StorageUsageState {
  final int? totalBytes;
  final bool isLoading;
  final String? error;
  final DateTime? lastRefresh;

  const StorageUsageState({
    this.totalBytes,
    this.isLoading = false,
    this.error,
    this.lastRefresh,
  });

  StorageUsageState copyWith({
    int? totalBytes,
    bool? isLoading,
    String? error,
    DateTime? lastRefresh,
  }) {
    return StorageUsageState(
      totalBytes: totalBytes ?? this.totalBytes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastRefresh: lastRefresh ?? this.lastRefresh,
    );
  }

  String get displaySize {
    if (totalBytes == null) return '--';
    if (totalBytes! < 1024) return '$totalBytes B';
    if (totalBytes! < 1024 * 1024) {
      return '${(totalBytes! / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes! < 1024 * 1024 * 1024) {
      return '${(totalBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Notifier for storage usage.
class StorageUsageNotifier extends StateNotifier<StorageUsageState> {
  final WebDavService _service;

  StorageUsageNotifier(this._service) : super(const StorageUsageState());

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _service.getStorageUsage();

    if (result.isSuccess) {
      state = state.copyWith(
        totalBytes: result.data,
        isLoading: false,
        lastRefresh: DateTime.now(),
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error?.userMessage,
      );
    }
  }

  /// Auto-fetch once if not yet loaded.
  void ensureLoaded() {
    if (state.totalBytes == null && !state.isLoading) {
      refresh();
    }
  }
}

/// Provider for storage usage (uses Text service).
final textStorageUsageProvider =
    StateNotifierProvider<StorageUsageNotifier, StorageUsageState>((ref) {
      final service = ref.watch(webDavTextServiceProvider);
      return StorageUsageNotifier(service);
    });

/// Provider for storage usage (uses Files service).
final filesStorageUsageProvider =
    StateNotifierProvider<StorageUsageNotifier, StorageUsageState>((ref) {
      final service = ref.watch(webDavFilesServiceProvider);
      return StorageUsageNotifier(service);
    });
