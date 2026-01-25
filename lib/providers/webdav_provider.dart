import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  Future<bool> deleteFile(String fileName) async {
    final result = await _service.deleteFile(fileName);

    if (result.isSuccess) {
      // Remove from local list
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

  /// Enable auto-pull with the specified refresh interval.
  void enable(int refreshIntervalSeconds) {
    _refreshIntervalSeconds = refreshIntervalSeconds;
    state = state.copyWith(isEnabled: true, error: null);
    _startPolling();
  }

  /// Disable auto-pull.
  void disable() {
    _isRunning = false;
    state = state.copyWith(isEnabled: false, isPolling: false);
  }

  /// Toggle auto-pull.
  void toggle(int refreshIntervalSeconds) {
    if (state.isEnabled) {
      disable();
    } else {
      enable(refreshIntervalSeconds);
    }
  }

  /// Pause auto-pull temporarily (during manual push/pull).
  void pause() {
    _isPaused = true;
  }

  /// Resume auto-pull after pause.
  void resume() {
    _isPaused = false;
  }

  /// Update refresh interval.
  void updateRefreshInterval(int seconds) {
    _refreshIntervalSeconds = seconds;
  }

  void _startPolling() {
    if (_isRunning) return;
    _isRunning = true;
    _pollLoop();
  }

  Future<void> _pollLoop() async {
    while (_isRunning && mounted) {
      // Skip check if paused
      if (!_isPaused) {
        await _checkForUpdates();
      }

      // Wait for interval AFTER the request completes
      if (_isRunning && mounted) {
        await Future.delayed(Duration(seconds: _refreshIntervalSeconds));
      }
    }
  }

  Future<void> _checkForUpdates() async {
    if (!mounted || _isPaused) return;

    state = state.copyWith(isPolling: true);

    final result = await _service.getBufferModifiedTime();

    if (!mounted) return;

    if (result.isSuccess) {
      final serverModTime = result.data;
      final lastKnownModTime = state.lastModifiedTime;

      state = state.copyWith(
        isPolling: false,
        lastCheckTime: DateTime.now(),
        error: null,
      );

      // If server has newer content, pull it
      if (serverModTime != null && !_isPaused) {
        if (lastKnownModTime == null || serverModTime.isAfter(lastKnownModTime)) {
          // Update last modified time first to prevent duplicate pulls
          state = state.copyWith(lastModifiedTime: serverModTime);
          // Trigger a pull
          await _ref.read(bufferProvider.notifier).pullFromRemote();
        }
      }
    } else {
      state = state.copyWith(
        isPolling: false,
        lastCheckTime: DateTime.now(),
        error: result.error?.userMessage,
      );
    }
  }

  /// Update the last modified time (call after pushing to server).
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
