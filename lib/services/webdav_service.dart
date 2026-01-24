import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path/path.dart' as p;
import '../models/app_config.dart';
import 'webdav_exceptions.dart';

/// Model for remote file information.
class RemoteFile {
  final String name;
  final String path;
  final int? size;
  final DateTime? modifiedTime;
  final bool isDirectory;

  const RemoteFile({
    required this.name,
    required this.path,
    this.size,
    this.modifiedTime,
    required this.isDirectory,
  });

  String get displaySize {
    if (size == null) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Service for WebDAV operations.
///
/// Handles connection, authentication, and all file operations
/// for the RemoteSend app.
class WebDavService {
  static const String _remoteSendFolder = '/RemoteSend';
  static const String _bufferFile = '/RemoteSend/buffer.txt';
  static const String _filesFolder = '/RemoteSend/Files';

  webdav.Client? _client;
  AppConfig? _config;

  /// Whether the service is connected with valid credentials.
  bool get isConnected => _client != null && _config != null;

  /// The base path for RemoteSend folder.
  String get remoteSendFolder => _remoteSendFolder;

  /// The path for the text buffer file.
  String get bufferFilePath => _bufferFile;

  /// The path for the files folder.
  String get filesFolderPath => _filesFolder;

  /// Initialize the WebDAV client with configuration.
  void initialize(AppConfig config) {
    if (!config.isConfigured) {
      _client = null;
      _config = null;
      return;
    }

    _config = config;
    _client = webdav.newClient(
      config.serverUrl,
      user: config.username,
      password: config.password,
      debug: false,
    );

    // Set timeouts - generous for large file transfers
    _client!.setHeaders({'accept-charset': 'utf-8'});
    _client!.setConnectTimeout(30000); // 30 seconds for connection
    _client!.setSendTimeout(600000); // 10 minutes for uploads
    _client!.setReceiveTimeout(600000); // 10 minutes for downloads
  }

  /// Disconnect and clear the client.
  void disconnect() {
    _client = null;
    _config = null;
  }

  /// Test the connection to the WebDAV server.
  Future<WebDavResult<bool>> testConnection() async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      // Try to ping/read the root to verify connection
      await _client!.ping();
      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Ensure the RemoteSend folder structure exists.
  ///
  /// Creates /RemoteSend, /RemoteSend/Files, and /RemoteSend/buffer.txt
  /// if they don't exist.
  Future<WebDavResult<bool>> ensureFolderStructure() async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      // Create /RemoteSend folder
      await _createDirectoryIfNotExists(_remoteSendFolder);

      // Create /RemoteSend/Files folder
      await _createDirectoryIfNotExists(_filesFolder);

      // Create buffer.txt if it doesn't exist
      await _createBufferFileIfNotExists();

      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Read the text buffer content.
  Future<WebDavResult<String>> readBuffer() async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final bytes = await _client!.read(_bufferFile);
      final content = utf8.decode(bytes);
      return WebDavResult.success(content);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        // Buffer doesn't exist yet, return empty string
        return const WebDavResult.success('');
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Write content to the text buffer.
  Future<WebDavResult<bool>> writeBuffer(String content) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      await _client!.write(_bufferFile, bytes);
      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Get the last modification time of the buffer file.
  Future<WebDavResult<DateTime?>> getBufferModifiedTime() async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      // Read directory to get file metadata
      final files = await _client!.readDir(_remoteSendFolder);
      final bufferFile = files.firstWhere(
        (f) => f.path == _bufferFile || f.name == 'buffer.txt',
        orElse: () => throw const WebDavNotFoundException(
          message: 'Buffer file not found',
        ),
      );
      return WebDavResult.success(bufferFile.mTime);
    } on WebDavException catch (e) {
      return WebDavResult.failure(e);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        return const WebDavResult.success(null);
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// List files in the Files folder.
  Future<WebDavResult<List<RemoteFile>>> listFiles() async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final files = await _client!.readDir(_filesFolder);
      final result = files
          .where((f) => !f.isDir!) // Only files, not directories
          .map((f) => RemoteFile(
                name: f.name ?? 'Unknown',
                path: f.path ?? '',
                size: f.size,
                modifiedTime: f.mTime,
                isDirectory: f.isDir ?? false,
              ))
          .toList();

      // Sort by modified time, newest first
      result.sort((a, b) {
        if (a.modifiedTime == null && b.modifiedTime == null) return 0;
        if (a.modifiedTime == null) return 1;
        if (b.modifiedTime == null) return -1;
        return b.modifiedTime!.compareTo(a.modifiedTime!);
      });

      return WebDavResult.success(result);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        // Folder doesn't exist, return empty list
        return const WebDavResult.success([]);
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Upload a file to the Files folder.
  ///
  /// [localPath] - Path to the local file.
  /// [remoteName] - Optional custom name for the remote file.
  /// [onProgress] - Optional callback for upload progress (0.0 to 1.0).
  Future<WebDavResult<bool>> uploadFile(
    String localPath, {
    String? remoteName,
    void Function(double progress)? onProgress,
  }) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return const WebDavResult.failure(
          WebDavNotFoundException(message: 'Local file not found'),
        );
      }

      final fileName = remoteName ?? p.basename(localPath);
      final remotePath = '$_filesFolder/$fileName';

      await _client!.writeFromFile(
        localPath,
        remotePath,
        onProgress: onProgress != null
            ? (count, total) => onProgress(count / total)
            : null,
      );

      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Download a file from the Files folder.
  ///
  /// [remoteName] - Name of the file on the server.
  /// [localPath] - Path where to save the file locally.
  /// [onProgress] - Optional callback for download progress (0.0 to 1.0).
  Future<WebDavResult<bool>> downloadFile(
    String remoteName,
    String localPath, {
    void Function(double progress)? onProgress,
  }) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final remotePath = '$_filesFolder/$remoteName';

      await _client!.read2File(
        remotePath,
        localPath,
        onProgress: onProgress != null
            ? (count, total) => onProgress(count / total)
            : null,
      );

      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Delete a file from the Files folder.
  Future<WebDavResult<bool>> deleteFile(String remoteName) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final remotePath = '$_filesFolder/$remoteName';
      await _client!.remove(remotePath);
      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  // Private helper methods

  Future<void> _createDirectoryIfNotExists(String path) async {
    try {
      await _client!.readDir(path);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        await _client!.mkdir(path);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _createBufferFileIfNotExists() async {
    try {
      await _client!.read(_bufferFile);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        // Create empty buffer file
        await _client!.write(_bufferFile, Uint8List(0));
      } else {
        rethrow;
      }
    }
  }

  bool _isNotFound(DioException e) {
    return e.response?.statusCode == 404;
  }

  WebDavException _mapException(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final message = error.message ?? error.toString();

      // Map HTTP status codes to specific exceptions
      if (statusCode != null) {
        switch (statusCode) {
          case 401:
            return WebDavAuthException(message: message, originalError: error);
          case 403:
            return WebDavPermissionException(
                message: message, originalError: error);
          case 404:
            return WebDavNotFoundException(
                message: message, originalError: error);
          case >= 500 && < 600:
            return WebDavServerException(
                message: message, originalError: error);
        }
      }

      // Map Dio error types
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return WebDavTimeoutException(
              message: message, originalError: error);
        case DioExceptionType.connectionError:
          return WebDavConnectionException(
              message: message, originalError: error);
        case DioExceptionType.badResponse:
          if (statusCode == 401) {
            return WebDavAuthException(message: message, originalError: error);
          }
          return WebDavServerException(message: message, originalError: error);
        default:
          return WebDavUnknownException(message: message, originalError: error);
      }
    }

    if (error is SocketException) {
      return WebDavConnectionException(
        message: error.message,
        originalError: error,
      );
    }

    if (error is FormatException) {
      return WebDavConfigException(
        message: 'Invalid server URL format',
        originalError: error,
      );
    }

    return WebDavUnknownException(
      message: error.toString(),
      originalError: error,
    );
  }
}
