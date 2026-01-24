import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../services/webdav_service.dart';
import '../services/webdav_exceptions.dart';
import 'config_provider.dart';

/// Provider for the WebDavService singleton.
final webDavServiceProvider = Provider<WebDavService>((ref) {
  final service = WebDavService();

  // Watch config changes and reinitialize service
  ref.listen<AsyncValue<AppConfig>>(configProvider, (previous, next) {
    next.whenData((config) {
      if (config.isConfigured) {
        service.initialize(config);
      } else {
        service.disconnect();
      }
    });
  });

  // Initialize with current config if available
  final currentConfig = ref.read(configProvider).valueOrNull;
  if (currentConfig != null && currentConfig.isConfigured) {
    service.initialize(currentConfig);
  }

  return service;
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

/// Provider for connection status management.
final connectionStatusProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionStatus>((ref) {
  final service = ref.watch(webDavServiceProvider);
  return ConnectionNotifier(service);
});

/// Provider for checking if service is ready to use.
final isServiceReadyProvider = Provider<bool>((ref) {
  final isConfigured = ref.watch(isConfiguredProvider);
  final connectionStatus = ref.watch(connectionStatusProvider);
  return isConfigured && connectionStatus.state == WebDavConnectionState.connected;
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

  const FileListState({
    this.files = const [],
    this.isLoading = false,
    this.error,
    this.lastRefresh,
  });

  FileListState copyWith({
    List<RemoteFile>? files,
    bool? isLoading,
    String? error,
    DateTime? lastRefresh,
  }) {
    return FileListState(
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastRefresh: lastRefresh ?? this.lastRefresh,
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

    final result = await _service.listFiles();

    if (result.isSuccess) {
      state = FileListState(
        files: result.data ?? [],
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

/// Provider for file list state management.
final fileListProvider =
    StateNotifierProvider<FileListNotifier, FileListState>((ref) {
  final service = ref.watch(webDavServiceProvider);
  return FileListNotifier(service);
});
