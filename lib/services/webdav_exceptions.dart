/// Custom exceptions for WebDAV operations with user-friendly messages.
library;

/// Base exception for all WebDAV-related errors.
sealed class WebDavException implements Exception {
  final String message;
  final String userMessage;
  final Object? originalError;

  const WebDavException({
    required this.message,
    required this.userMessage,
    this.originalError,
  });

  @override
  String toString() => 'WebDavException: $message';
}

/// Connection failed - network issues, server unreachable.
class WebDavConnectionException extends WebDavException {
  const WebDavConnectionException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'Cannot connect to server. Check your internet connection and server URL.');
}

/// Authentication failed - wrong username/password.
class WebDavAuthException extends WebDavException {
  const WebDavAuthException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'Authentication failed. Check your username and password.');
}

/// Resource not found - file or folder doesn't exist.
class WebDavNotFoundException extends WebDavException {
  const WebDavNotFoundException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'Resource not found on the server.');
}

/// Permission denied - no access to resource.
class WebDavPermissionException extends WebDavException {
  const WebDavPermissionException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'Permission denied. Check your access rights on the server.');
}

/// Server error - 5xx responses.
class WebDavServerException extends WebDavException {
  const WebDavServerException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'Server error. Please try again later.');
}

/// Invalid URL or configuration.
class WebDavConfigException extends WebDavException {
  const WebDavConfigException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'Invalid server configuration. Check the server URL.');
}

/// Timeout during operation.
class WebDavTimeoutException extends WebDavException {
  const WebDavTimeoutException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'Connection timed out. Server may be slow or unreachable.');
}

/// Unknown/unexpected error.
class WebDavUnknownException extends WebDavException {
  const WebDavUnknownException({
    required super.message,
    super.originalError,
    String? userMessage,
  }) : super(userMessage: userMessage ?? 'An unexpected error occurred. Please try again.');
}

/// Result wrapper for WebDAV operations.
class WebDavResult<T> {
  final T? data;
  final WebDavException? error;

  const WebDavResult.success(this.data) : error = null;
  const WebDavResult.failure(this.error) : data = null;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;

  /// Get data or throw if error.
  T get dataOrThrow {
    if (error != null) throw error!;
    return data as T;
  }

  /// Map success value to another type.
  WebDavResult<R> map<R>(R Function(T) mapper) {
    if (isSuccess) {
      return WebDavResult.success(mapper(data as T));
    }
    return WebDavResult.failure(error);
  }

  /// Execute callback on success, return original result.
  WebDavResult<T> onSuccess(void Function(T) callback) {
    if (isSuccess) callback(data as T);
    return this;
  }

  /// Execute callback on failure, return original result.
  WebDavResult<T> onFailure(void Function(WebDavException) callback) {
    if (isFailure) callback(error!);
    return this;
  }
}
