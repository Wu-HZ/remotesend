import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path/path.dart' as p;
import '../models/app_config.dart';
import '../models/server_config.dart';
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
  static const String _messagesFolder = '/RemoteSend/Messages';

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

  /// The path for the messages folder.
  String get messagesFolderPath => _messagesFolder;

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

  /// Initialize the WebDAV client with a server configuration directly.
  void initializeWithServer(ServerConfig server) {
    if (!server.isConfigured) {
      _client = null;
      _config = null;
      return;
    }

    // Create a minimal AppConfig for backward compatibility
    _config = AppConfig(
      servers: [server],
      activeTextServerId: server.id,
      activeFilesServerId: server.id,
    );

    _client = webdav.newClient(
      server.serverUrl,
      user: server.username,
      password: server.password,
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
  /// Creates /RemoteSend, /RemoteSend/Files, /RemoteSend/Messages, and /RemoteSend/buffer.txt
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

      // Create /RemoteSend/Messages folder
      await _createDirectoryIfNotExists(_messagesFolder);

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

  /// List files and folders in the specified path (defaults to Files folder).
  Future<WebDavResult<List<RemoteFile>>> listFiles([String? subPath]) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final targetPath = subPath != null && subPath.isNotEmpty
          ? '$_filesFolder/$subPath'
          : _filesFolder;

      final files = await _client!.readDir(targetPath);
      final result = files
          .map((f) => RemoteFile(
                name: f.name ?? 'Unknown',
                path: f.path ?? '',
                size: f.size,
                modifiedTime: f.mTime,
                isDirectory: f.isDir ?? false,
              ))
          .toList();

      // Sort: directories first, then by modified time (newest first)
      result.sort((a, b) {
        // Directories first
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        // Then by modified time
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

  /// Create a directory on the server.
  Future<WebDavResult<bool>> createRemoteDirectory(String remotePath) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      await _client!.mkdir(remotePath);
      return const WebDavResult.success(true);
    } on DioException catch (e) {
      // Directory might already exist (405 Method Not Allowed)
      if (e.response?.statusCode == 405) {
        return const WebDavResult.success(true);
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Upload a file to a specific remote path (supports subdirectories).
  Future<WebDavResult<bool>> uploadFileToPath(
    String localPath,
    String remotePath, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
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

      await _client!.writeFromFile(
        localPath,
        remotePath,
        onProgress: onProgress != null
            ? (count, total) => onProgress(count / total)
            : null,
        cancelToken: cancelToken,
      );

      return const WebDavResult.success(true);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return const WebDavResult.failure(
          WebDavConfigException(message: 'Upload cancelled'),
        );
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Upload a folder and all its contents to the Files folder.
  ///
  /// [localFolderPath] - Path to the local folder.
  /// [onProgress] - Callback with (currentFile, totalFiles, fileProgress).
  /// Returns the number of files uploaded.
  Future<WebDavResult<int>> uploadFolder(
    String localFolderPath, {
    void Function(String fileName, int current, int total, double fileProgress)? onProgress,
  }) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final localFolder = Directory(localFolderPath);
      if (!await localFolder.exists()) {
        return const WebDavResult.failure(
          WebDavNotFoundException(message: 'Local folder not found'),
        );
      }

      final folderName = p.basename(localFolderPath);
      final remoteFolderPath = '$_filesFolder/$folderName';

      // Create root folder on server
      await createRemoteDirectory(remoteFolderPath);

      // Collect all files to upload
      final files = <File>[];
      final relativePaths = <String>[];

      await for (final entity in localFolder.list(recursive: true)) {
        if (entity is File) {
          files.add(entity);
          // Get path relative to the source folder
          final relativePath = p.relative(entity.path, from: localFolderPath);
          relativePaths.add(relativePath);
        } else if (entity is Directory) {
          // Create directory on server
          final relativePath = p.relative(entity.path, from: localFolderPath);
          final remoteDir = '$remoteFolderPath/$relativePath'.replaceAll('\\', '/');
          await createRemoteDirectory(remoteDir);
        }
      }

      // Upload each file
      int uploadedCount = 0;
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final relativePath = relativePaths[i].replaceAll('\\', '/');
        final remoteFilePath = '$remoteFolderPath/$relativePath';

        final result = await uploadFileToPath(
          file.path,
          remoteFilePath,
          onProgress: onProgress != null
              ? (progress) => onProgress(p.basename(file.path), i + 1, files.length, progress)
              : null,
        );

        if (result.isSuccess) {
          uploadedCount++;
        }
      }

      return WebDavResult.success(uploadedCount);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Download a file from the Files folder.
  ///
  /// [remoteName] - Name of the file on the server.
  /// [localPath] - Path where to save the file locally.
  /// [onProgress] - Optional callback for download progress with (downloaded, total) bytes.
  Future<WebDavResult<bool>> downloadFile(
    String remoteName,
    String localPath, {
    void Function(int downloaded, int total)? onProgress,
    CancelToken? cancelToken,
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
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      return const WebDavResult.success(true);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return const WebDavResult.failure(
          WebDavConfigException(message: 'Download cancelled'),
        );
      }
      return WebDavResult.failure(_mapException(e));
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

  // ==================== Messages Folder Operations ====================

  /// Read messages file for a specific date.
  ///
  /// [date] - Date string in format 'yyyy-MM-dd'.
  /// Returns the JSON content of the messages file.
  Future<WebDavResult<String>> readMessagesFile(String date) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final remotePath = '$_messagesFolder/$date.json';
      final bytes = await _client!.read(remotePath);
      final content = utf8.decode(bytes);
      return WebDavResult.success(content);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        // File doesn't exist yet, return empty array
        return const WebDavResult.success('[]');
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Write messages file for a specific date.
  ///
  /// [date] - Date string in format 'yyyy-MM-dd'.
  /// [content] - JSON content to write.
  Future<WebDavResult<bool>> writeMessagesFile(String date, String content) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final remotePath = '$_messagesFolder/$date.json';
      final bytes = Uint8List.fromList(utf8.encode(content));
      await _client!.write(remotePath, bytes);
      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// List available message dates.
  ///
  /// Returns a list of date strings (yyyy-MM-dd) for which message files exist.
  Future<WebDavResult<List<String>>> listMessageDates() async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final files = await _client!.readDir(_messagesFolder);
      final dates = files
          .where((f) => f.name?.endsWith('.json') == true && f.isDir != true)
          .map((f) => f.name!.replaceAll('.json', ''))
          .toList();
      dates.sort((a, b) => b.compareTo(a)); // Most recent first
      return WebDavResult.success(dates);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        return const WebDavResult.success([]);
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Get the last modification time of a messages file for [date].
  ///
  /// [date] - Date string in format 'yyyy-MM-dd'.
  Future<WebDavResult<DateTime?>> getMessagesModifiedTime(String date) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final files = await _client!.readDir(_messagesFolder);
      final targetFile = files.firstWhere(
        (f) => f.name == '$date.json',
        orElse: () => throw const WebDavNotFoundException(
          message: 'Messages file not found',
        ),
      );
      return WebDavResult.success(targetFile.mTime);
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

  /// Download a file from a specific remote path.
  Future<WebDavResult<bool>> downloadFileFromPath(
    String remotePath,
    String localPath, {
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      await _client!.read2File(
        remotePath,
        localPath,
        onProgress: onProgress,
      );

      return const WebDavResult.success(true);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Download a folder and all its contents from the Files folder.
  ///
  /// [remoteFolderName] - Name of the folder on the server (relative to Files folder).
  /// [localFolderPath] - Path where to save the folder locally.
  /// [onFilesCollected] - Callback with list of files to download before starting.
  /// [onProgress] - Callback with (fileName, currentFileIndex, totalFiles, downloadedBytes, totalBytes).
  /// Returns the number of files downloaded.
  Future<WebDavResult<int>> downloadFolder(
    String remoteFolderName,
    String localFolderPath, {
    void Function(List<RemoteFileInfo> files)? onFilesCollected,
    void Function(String fileName, int current, int total, int downloadedBytes, int totalBytes)? onProgress,
  }) async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final remoteFolderPath = '$_filesFolder/$remoteFolderName';

      // Collect all files to download recursively
      final filesToDownload = <RemoteFileInfo>[];
      await _collectFilesRecursively(remoteFolderPath, '', filesToDownload);

      // Notify about files collected
      onFilesCollected?.call(filesToDownload);

      if (filesToDownload.isEmpty) {
        // Create empty folder locally
        await Directory(localFolderPath).create(recursive: true);
        return const WebDavResult.success(0);
      }

      // Download each file
      int downloadedCount = 0;
      for (int i = 0; i < filesToDownload.length; i++) {
        final fileInfo = filesToDownload[i];
        final localFilePath = p.join(localFolderPath, fileInfo.relativePath);

        // Ensure parent directory exists
        final parentDir = Directory(p.dirname(localFilePath));
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        final result = await downloadFileFromPath(
          fileInfo.remotePath,
          localFilePath,
          onProgress: onProgress != null
              ? (downloaded, total) => onProgress(fileInfo.fileName, i + 1, filesToDownload.length, downloaded, total)
              : null,
        );

        if (result.isSuccess) {
          downloadedCount++;
        }
      }

      return WebDavResult.success(downloadedCount);
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }

  /// Recursively collect all files in a remote directory.
  Future<void> _collectFilesRecursively(
    String remotePath,
    String relativePath,
    List<RemoteFileInfo> files,
  ) async {
    final items = await _client!.readDir(remotePath);

    for (final item in items) {
      final itemName = item.name ?? '';
      final itemPath = item.path ?? '$remotePath/$itemName';
      final itemRelativePath = relativePath.isEmpty ? itemName : '$relativePath/$itemName';

      if (item.isDir == true) {
        // Recursively collect files from subdirectory
        await _collectFilesRecursively(itemPath, itemRelativePath, files);
      } else {
        // Add file to list
        files.add(RemoteFileInfo(
          remotePath: itemPath,
          relativePath: itemRelativePath,
          fileName: itemName,
          fileSize: item.size ?? 0,
        ));
      }
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

  /// Get total storage usage by recursively summing all file sizes in RemoteSend.
  Future<WebDavResult<int>> getStorageUsage() async {
    if (_client == null) {
      return const WebDavResult.failure(
        WebDavConfigException(message: 'Client not initialized'),
      );
    }

    try {
      final propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:getcontentlength/>
    <D:resourcetype/>
  </D:prop>
</D:propfind>''';

      final response = await _client!.c.req<String>(
        _client!,
        'PROPFIND',
        _remoteSendFolder,
        data: propfindBody,
        optionsHandler: (options) {
          options.headers?['Depth'] = 'infinity';
          options.headers?['Content-Type'] = 'application/xml;charset=UTF-8';
        },
      );

      if (response.statusCode != 207) {
        return WebDavResult.failure(
          WebDavServerException(message: 'Server returned ${response.statusCode}'),
        );
      }

      // Parse XML to sum file sizes
      final xmlStr = response.data?.toString() ?? '';
      int totalSize = 0;

      // Match each <D:response> block: href + propstat with 200 status only
      final responseRegex = RegExp(
        r'<D:response>(.*?)</D:response>',
        dotAll: true,
      );

      for (final match in responseRegex.allMatches(xmlStr)) {
        final block = match.group(1) ?? '';
        // Skip non-200 propstat blocks
        if (!block.contains('<D:status>HTTP/1.1 200 OK</D:status>')) continue;
        // Skip directories (those with <D:collection/>)
        if (block.contains('<D:collection')) continue;
        // Extract size
        final sizeMatch =
            RegExp(r'<D:getcontentlength>(\d+)</D:getcontentlength>')
                .firstMatch(block);
        if (sizeMatch != null) {
          totalSize += int.parse(sizeMatch.group(1)!);
        }
      }

      return WebDavResult.success(totalSize);
    } on DioException catch (e) {
      if (_isNotFound(e)) {
        return const WebDavResult.success(0);
      }
      return WebDavResult.failure(_mapException(e));
    } catch (e) {
      return WebDavResult.failure(_mapException(e));
    }
  }
}

/// Helper class to store file info for recursive folder operations.
class RemoteFileInfo {
  final String remotePath;
  final String relativePath;
  final String fileName;
  final int fileSize;

  RemoteFileInfo({
    required this.remotePath,
    required this.relativePath,
    required this.fileName,
    required this.fileSize,
  });
}
