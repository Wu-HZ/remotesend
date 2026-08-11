import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/server_config.dart';
import '../services/webdav_service.dart';
import '../services/webdav_exceptions.dart';
import 'config_provider.dart';
import 'message_history_provider.dart';

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
enum WebDavConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

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

  ConnectionNotifier(this._service) : super(const ConnectionStatus.disconnected());

  /// Test the connection and update status.
  Future<bool> testConnection() async {
    state = ConnectionStatus(
      state: WebDavConnectionState.connecting,
      lastChecked: state.lastChecked,
    );

    final result = await _service.testConnection();

    if (result.isSuccess) {
      state = ConnectionStatus(
        state: WebDavConnectionState.connected,
        lastChecked: DateTime.now(),
      );
      return true;
    } else {
      state = ConnectionStatus(
        state: WebDavConnectionState.error,
        errorMessage: result.error?.userMessage,
        lastChecked: DateTime.now(),
      );
      return false;
    }
  }

  /// Initialize the RemoteSend folder structure on the server.
  Future<WebDavResult<bool>> initializeFolderStructure() async {
    return _service.ensureFolderStructure();
  }

  /// Reset connection status.
  void reset() {
    state = const ConnectionStatus.disconnected();
  }
}

/// Provider for connection status management for Text Bridge.
final textConnectionStatusProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionStatus>((ref) {
  final service = ref.watch(webDavTextServiceProvider);
  return ConnectionNotifier(service);
});

/// Provider for connection status management for File Depot.
final filesConnectionStatusProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionStatus>((ref) {
  final service = ref.watch(webDavFilesServiceProvider);
  return ConnectionNotifier(service);
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
  return isConfigured && connectionStatus.state == WebDavConnectionState.connected;
});

/// Provider for checking if files service is ready to use.
final isFilesServiceReadyProvider = Provider<bool>((ref) {
  final isConfigured = ref.watch(isFilesConfiguredProvider);
  final connectionStatus = ref.watch(filesConnectionStatusProvider);
  return isConfigured && connectionStatus.state == WebDavConnectionState.connected;
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
      state = BufferState(
        content: result.data ?? '',
        lastSync: DateTime.now(),
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

  /// Push content to the remote buffer.
  Future<bool> pushToRemote(String content) async {
    state = state.copyWith(isSaving: true, error: null);

    final result = await _service.writeBuffer(content);

    if (result.isSuccess) {
      state = BufferState(
        content: content,
        lastSync: DateTime.now(),
      );
      return true;
    } else {
      state = state.copyWith(
        isSaving: false,
        error: result.error?.userMessage,
      );
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
final bufferProvider =
    StateNotifierProvider<BufferNotifier, BufferState>((ref) {
  final service = ref.watch(webDavServiceProvider);
  return BufferNotifier(service);
});

/// State for the file list.
class FileListState {
  final List<RemoteFile> files;
  final bool isLoading;
  final String? error;
  final DateTime? lastRefresh;
  final String currentPath; // Current path relative to Files folder (empty = root)

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

  FileListNotifier(this._service) : super(const FileListState());

  /// Refresh the file list from the server.
  Future<bool> refresh() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _service.listFiles(state.currentPath);

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

  /// Navigate into a folder.
  Future<bool> navigateToFolder(String folderName) async {
    final newPath = state.currentPath.isEmpty
        ? folderName
        : '${state.currentPath}/$folderName';

    state = state.copyWith(isLoading: true, error: null, currentPath: newPath);

    final result = await _service.listFiles(newPath);

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
        currentPath: state.currentPath,
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

    state = state.copyWith(isLoading: true, error: null, currentPath: newPath);

    final result = await _service.listFiles(newPath.isEmpty ? null : newPath);

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
    state = state.copyWith(isLoading: true, error: null, currentPath: '');

    final result = await _service.listFiles();

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
    final result = await _service.deleteFile(filePath);

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

  /// Clear the file list.
  void clear() {
    state = const FileListState();
  }
}

/// Provider for file list state management (uses Files service).
final fileListProvider =
    StateNotifierProvider<FileListNotifier, FileListState>((ref) {
  final service = ref.watch(webDavFilesServiceProvider);
  return FileListNotifier(service);
});

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

/// State for auto-pull functionality.
class AutoPullState {
  final bool isEnabled;
  final bool isPolling;
  final DateTime? lastModifiedTime;
  final DateTime? lastCheckTime;
  final String? error;

  const AutoPullState({
    this.isEnabled = false,
    this.isPolling = false,
    this.lastModifiedTime,
    this.lastCheckTime,
    this.error,
  });

  AutoPullState copyWith({
    bool? isEnabled,
    bool? isPolling,
    DateTime? lastModifiedTime,
    DateTime? lastCheckTime,
    String? error,
  }) {
    return AutoPullState(
      isEnabled: isEnabled ?? this.isEnabled,
      isPolling: isPolling ?? this.isPolling,
      lastModifiedTime: lastModifiedTime ?? this.lastModifiedTime,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      error: error,
    );
  }
}

/// Notifier for auto-pull functionality.
class AutoPullNotifier extends StateNotifier<AutoPullState> {
  final WebDavService _service;
  final Ref _ref;
  bool _isRunning = false;
  bool _isPaused = false;
  int _refreshIntervalSeconds = 3;

  AutoPullNotifier(this._service, this._ref) : super(const AutoPullState());

  void enable(int refreshIntervalSeconds) {
    _refreshIntervalSeconds = refreshIntervalSeconds;
    state = state.copyWith(isEnabled: true, error: null);
    _isRunning = true;
    _pollLoop();
  }

  void disable() {
    _isRunning = false;
    state = state.copyWith(isEnabled: false, isPolling: false);
  }

  void toggle(int refreshIntervalSeconds) {
    if (state.isEnabled) {
      disable();
    } else {
      enable(refreshIntervalSeconds);
    }
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  void updateRefreshInterval(int seconds) {
    _refreshIntervalSeconds = seconds;
  }

  void _pollLoop() {
    Future.doWhile(() async {
      if (!_isRunning || !mounted) return false;

      if (!_isPaused) {
        try {
          await _checkForUpdates();
        } catch (_) {}
      }

      if (!_isRunning || !mounted) return false;

      await Future.delayed(Duration(seconds: _refreshIntervalSeconds));
      return _isRunning && mounted;
    });
  }

  Future<void> _checkForUpdates() async {
    if (!mounted || _isPaused) return;

    state = state.copyWith(isPolling: true);

    try {
      final today = _getTodayDate();
      final result = await _service.getMessagesModifiedTime(today);

      if (!mounted) return;

      if (result.isSuccess) {
        final serverModTime = result.data;
        final lastKnownModTime = state.lastModifiedTime;

        state = state.copyWith(
          isPolling: false,
          lastCheckTime: DateTime.now(),
          error: null,
        );

        if (serverModTime != null && !_isPaused) {
          if (lastKnownModTime == null ||
              serverModTime.isAfter(lastKnownModTime)) {
            state = state.copyWith(lastModifiedTime: serverModTime);
            await _ref.read(messageHistoryProvider.notifier).refresh();
          }
        }
      } else {
        state = state.copyWith(
          isPolling: false,
          lastCheckTime: DateTime.now(),
          error: result.error?.userMessage,
        );
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isPolling: false,
        lastCheckTime: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  String _getTodayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void updateLastModifiedTime(DateTime time) {
    state = state.copyWith(lastModifiedTime: time);
  }

  @override
  void dispose() {
    _isRunning = false;
    super.dispose();
  }
}

/// Provider for auto-pull state management.
final autoPullProvider =
    StateNotifierProvider<AutoPullNotifier, AutoPullState>((ref) {
  final service = ref.watch(webDavServiceProvider);
  return AutoPullNotifier(service, ref);
});
