import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../models/server_config.dart';

const String _emptyPayloadHash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// Metadata returned by S3 object and prefix listings.
class S3ObjectInfo {
  final String key;
  final int size;
  final DateTime? modifiedTime;
  final bool isDirectory;

  const S3ObjectInfo({
    required this.key,
    this.size = 0,
    this.modifiedTime,
    this.isDirectory = false,
  });
}

/// AWS Signature Version 4 implementation used for S3-compatible providers.
class S3Signer {
  final String accessKey;
  final String secretKey;
  final String region;
  final String sessionToken;

  const S3Signer({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    this.sessionToken = '',
  });

  Map<String, String> sign({
    required String method,
    required Uri uri,
    required DateTime dateTime,
    required String payloadHash,
    Map<String, String> headers = const {},
  }) {
    final utc = dateTime.toUtc();
    final amzDate = _formatAmzDate(utc);
    final dateStamp = amzDate.substring(0, 8);
    final requestHeaders = <String, String>{
      ...headers,
      'host': _hostHeader(uri),
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      if (sessionToken.isNotEmpty) 'x-amz-security-token': sessionToken,
    };

    final normalized = <String, String>{};
    for (final entry in requestHeaders.entries) {
      normalized[entry.key.toLowerCase()] = entry.value.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
    }
    final headerNames = normalized.keys.toList()..sort();
    final canonicalHeaders = headerNames
        .map((name) => '$name:${normalized[name]}\n')
        .join();
    final signedHeaders = headerNames.join(';');
    final canonicalRequest = [
      method.toUpperCase(),
      _canonicalUri(uri),
      _canonicalQuery(uri),
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final scope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final signingKey = _signatureKey(secretKey, dateStamp, region, 's3');
    final signature = _hex(
      Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes,
    );

    return {
      ...requestHeaders,
      'authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKey/$scope,'
          'SignedHeaders=$signedHeaders,Signature=$signature',
    };
  }

  static String _canonicalUri(Uri uri) {
    if (uri.pathSegments.isEmpty) return '/';
    final encoded = uri.pathSegments.map(_awsEncode).join('/');
    return '/$encoded';
  }

  static String _canonicalQuery(Uri uri) {
    final pairs = <MapEntry<String, String>>[];
    uri.queryParametersAll.forEach((name, values) {
      if (values.isEmpty) {
        pairs.add(MapEntry(_awsEncode(name), ''));
      } else {
        for (final value in values) {
          pairs.add(MapEntry(_awsEncode(name), _awsEncode(value)));
        }
      }
    });
    pairs.sort((a, b) {
      final nameOrder = a.key.compareTo(b.key);
      return nameOrder != 0 ? nameOrder : a.value.compareTo(b.value);
    });
    return pairs.map((pair) => '${pair.key}=${pair.value}').join('&');
  }

  static String _hostHeader(Uri uri) {
    final defaultPort =
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
    return defaultPort ? uri.host : '${uri.host}:${uri.port}';
  }

  static String _formatAmzDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}'
        '${two(date.month)}${two(date.day)}T'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}Z';
  }

  static List<int> _signatureKey(
    String secret,
    String date,
    String region,
    String service,
  ) {
    List<int> hmac(List<int> key, String value) =>
        Hmac(sha256, key).convert(utf8.encode(value)).bytes;
    final dateKey = hmac(utf8.encode('AWS4$secret'), date);
    final regionKey = hmac(dateKey, region);
    final serviceKey = hmac(regionKey, service);
    return hmac(serviceKey, 'aws4_request');
  }

  static String _hex(List<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  static String _awsEncode(String value) =>
      Uri.encodeComponent(value).replaceAll('%7E', '~').replaceAll('%7e', '~');
}

/// Minimal S3 object client supporting AWS S3, MinIO, R2 and compatible APIs.
class S3StorageClient {
  static const int _multipartThreshold = 64 * 1024 * 1024;
  static const int _minimumPartSize = 8 * 1024 * 1024;

  final ServerConfig config;
  final Dio _dio;
  late final Uri _endpoint;
  late final S3Signer _signer;

  S3StorageClient(this.config, {Dio? dio}) : _dio = dio ?? Dio() {
    _endpoint = Uri.parse(config.serverUrl.trim());
    _signer = S3Signer(
      accessKey: config.s3AccessKey,
      secretKey: config.s3SecretKey,
      region: config.s3Region,
      sessionToken: config.s3SessionToken,
    );
    _dio.options
      ..connectTimeout = const Duration(seconds: 30)
      ..sendTimeout = const Duration(minutes: 10)
      ..receiveTimeout = const Duration(minutes: 10);
  }

  Future<void> testConnection() async {
    await _request<String>(
      'GET',
      '',
      query: const {'list-type': '2', 'max-keys': '1'},
      responseType: ResponseType.plain,
    );
  }

  Future<void> putBytes(String key, List<int> bytes) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    await _request<void>(
      'PUT',
      key,
      data: data,
      payloadHash: sha256.convert(data).toString(),
      headers: {'content-length': '${data.length}'},
    );
  }

  Future<Uint8List> getBytes(String key) async {
    final response = await _request<List<int>>(
      'GET',
      key,
      responseType: ResponseType.bytes,
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  Future<S3ObjectInfo?> headObject(String key) async {
    try {
      final response = await _request<void>('HEAD', key);
      return S3ObjectInfo(
        key: key,
        size: int.tryParse(response.headers.value('content-length') ?? '') ?? 0,
        modifiedTime: _parseHttpDate(response.headers.value('last-modified')),
        isDirectory: key.endsWith('/'),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<S3ObjectInfo>> listDirectory(String prefix) async {
    final normalizedPrefix = _directoryPrefix(prefix);
    final page = await _listObjects(prefix: normalizedPrefix, delimiter: '/');
    final entries = <String, S3ObjectInfo>{};

    for (final commonPrefix in page.prefixes) {
      final name = _basename(
        commonPrefix.substring(0, commonPrefix.length - 1),
      );
      if (name.isEmpty) continue;
      entries['d:$name'] = S3ObjectInfo(key: commonPrefix, isDirectory: true);
    }
    for (final object in page.objects) {
      if (object.key == normalizedPrefix) continue;
      final relative = object.key.substring(normalizedPrefix.length);
      if (relative.isEmpty || relative.contains('/')) continue;
      if (object.key.endsWith('/')) {
        final name = _basename(object.key.substring(0, object.key.length - 1));
        entries['d:$name'] = S3ObjectInfo(
          key: object.key,
          modifiedTime: object.modifiedTime,
          isDirectory: true,
        );
      } else {
        entries['f:$relative'] = object;
      }
    }
    return entries.values.toList();
  }

  Future<List<S3ObjectInfo>> listAll(String prefix) async {
    final result = <S3ObjectInfo>[];
    String? continuationToken;
    do {
      final page = await _listObjects(
        prefix: prefix,
        continuationToken: continuationToken,
      );
      result.addAll(page.objects);
      continuationToken = page.nextContinuationToken;
    } while (continuationToken != null && continuationToken.isNotEmpty);
    return result;
  }

  Future<_S3ListPage> _listObjects({
    required String prefix,
    String? delimiter,
    String? continuationToken,
  }) async {
    final response = await _request<String>(
      'GET',
      '',
      query: {
        'list-type': '2',
        'prefix': prefix,
        if (delimiter != null) 'delimiter': delimiter,
        if (continuationToken != null) 'continuation-token': continuationToken,
      },
      responseType: ResponseType.plain,
    );
    final document = XmlDocument.parse(response.data ?? '<ListBucketResult/>');
    final objects = <S3ObjectInfo>[];
    for (final contents in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'Contents',
    )) {
      final key = _childText(contents, 'Key');
      if (key == null) continue;
      objects.add(
        S3ObjectInfo(
          key: key,
          size: int.tryParse(_childText(contents, 'Size') ?? '') ?? 0,
          modifiedTime: DateTime.tryParse(
            _childText(contents, 'LastModified') ?? '',
          ),
          isDirectory: key.endsWith('/'),
        ),
      );
    }
    final prefixes = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'CommonPrefixes')
        .map((element) => _childText(element, 'Prefix'))
        .whereType<String>()
        .toList();
    final truncated = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'IsTruncated')
        .map((element) => element.innerText.toLowerCase() == 'true')
        .firstOrNull;
    final nextToken = truncated == true
        ? document.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'NextContinuationToken')
              .map((element) => element.innerText)
              .firstOrNull
        : null;
    return _S3ListPage(
      objects: objects,
      prefixes: prefixes,
      nextContinuationToken: nextToken,
    );
  }

  Future<void> createDirectory(String key) {
    return putBytes(_directoryPrefix(key), const []);
  }

  Future<void> uploadFile(
    String localPath,
    String key, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(localPath);
    final length = await file.length();
    if (length >= _multipartThreshold) {
      await _multipartUpload(
        file,
        key,
        length,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      return;
    }

    await _request<void>(
      'PUT',
      key,
      data: file.openRead(),
      payloadHash: 'UNSIGNED-PAYLOAD',
      headers: {'content-length': '$length'},
      cancelToken: cancelToken,
      onSendProgress: onProgress == null || length == 0
          ? null
          : (sent, _) => onProgress((sent / length).clamp(0, 1)),
    );
    onProgress?.call(1);
  }

  Future<void> _multipartUpload(
    File file,
    String key,
    int fileLength, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    String? uploadId;
    try {
      final createResponse = await _request<String>(
        'POST',
        key,
        query: const {'uploads': ''},
        responseType: ResponseType.plain,
        cancelToken: cancelToken,
      );
      final createDocument = XmlDocument.parse(createResponse.data ?? '');
      uploadId = createDocument.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'UploadId')
          .map((element) => element.innerText)
          .firstOrNull;
      if (uploadId == null || uploadId.isEmpty) {
        throw const FormatException('S3 multipart response has no UploadId');
      }

      final calculatedSize = (fileLength / 10000).ceil();
      final partSize = math.max(_minimumPartSize, calculatedSize);
      final parts = <_CompletedPart>[];
      var offset = 0;
      var partNumber = 1;
      while (offset < fileLength) {
        final end = math.min(offset + partSize, fileLength);
        final length = end - offset;
        final baseOffset = offset;
        final response = await _request<void>(
          'PUT',
          key,
          query: {'partNumber': '$partNumber', 'uploadId': uploadId},
          data: file.openRead(offset, end),
          payloadHash: 'UNSIGNED-PAYLOAD',
          headers: {'content-length': '$length'},
          cancelToken: cancelToken,
          onSendProgress: onProgress == null
              ? null
              : (sent, _) =>
                    onProgress(((baseOffset + sent) / fileLength).clamp(0, 1)),
        );
        final etag = response.headers.value('etag');
        if (etag == null || etag.isEmpty) {
          throw const FormatException('S3 multipart response has no ETag');
        }
        parts.add(_CompletedPart(partNumber, etag));
        offset = end;
        partNumber++;
      }

      final completeXml = StringBuffer('<CompleteMultipartUpload>');
      for (final part in parts) {
        completeXml
          ..write('<Part><PartNumber>${part.number}</PartNumber><ETag>')
          ..write(_xmlEscape(part.etag))
          ..write('</ETag></Part>');
      }
      completeXml.write('</CompleteMultipartUpload>');
      final completeBytes = utf8.encode(completeXml.toString());
      await _request<String>(
        'POST',
        key,
        query: {'uploadId': uploadId},
        data: completeBytes,
        payloadHash: sha256.convert(completeBytes).toString(),
        headers: {
          'content-type': 'application/xml',
          'content-length': '${completeBytes.length}',
        },
        responseType: ResponseType.plain,
        cancelToken: cancelToken,
      );
      onProgress?.call(1);
    } catch (_) {
      if (uploadId != null) {
        try {
          await _request<void>('DELETE', key, query: {'uploadId': uploadId});
        } catch (_) {
          // The original upload error is more useful than abort failure.
        }
      }
      rethrow;
    }
  }

  Future<void> downloadFile(
    String key,
    String localPath, {
    void Function(int downloaded, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final response = await _request<ResponseBody>(
      'GET',
      key,
      responseType: ResponseType.stream,
      cancelToken: cancelToken,
    );
    final body = response.data!;
    final total =
        int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
    final target = File(localPath);
    await target.parent.create(recursive: true);
    final sink = target.openWrite();
    var downloaded = 0;
    try {
      await for (final chunk in body.stream) {
        if (cancelToken?.isCancelled == true) {
          throw DioException.requestCancelled(
            requestOptions: response.requestOptions,
            reason: cancelToken?.cancelError,
          );
        }
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress?.call(downloaded, total);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await target.exists()) await target.delete();
      rethrow;
    }
    await sink.close();
    onProgress?.call(downloaded, total < 0 ? downloaded : total);
  }

  Future<void> deleteObject(String key) async {
    await _request<void>('DELETE', key);
  }

  Future<void> deletePrefix(String prefix) async {
    final objects = await listAll(prefix);
    for (final object in objects) {
      await deleteObject(object.key);
    }
  }

  Future<void> copyObject(String sourceKey, String destinationKey) async {
    final encodedSource = sourceKey
        .split('/')
        .map(S3Signer._awsEncode)
        .join('/');
    await _request<void>(
      'PUT',
      destinationKey,
      headers: {'x-amz-copy-source': '/${config.s3Bucket}/$encodedSource'},
    );
  }

  Future<void> moveObject(String sourceKey, String destinationKey) async {
    await copyObject(sourceKey, destinationKey);
    await deleteObject(sourceKey);
  }

  Future<void> movePrefix(String sourcePrefix, String destinationPrefix) async {
    final source = _directoryPrefix(sourcePrefix);
    final destination = _directoryPrefix(destinationPrefix);
    final objects = await listAll(source);
    for (final object in objects) {
      final suffix = object.key.substring(source.length);
      await copyObject(object.key, '$destination$suffix');
    }
    for (final object in objects) {
      await deleteObject(object.key);
    }
  }

  Future<int> storageUsage(String prefix) async {
    final objects = await listAll(prefix);
    return objects.fold<int>(0, (total, object) => total + object.size);
  }

  Future<Response<T>> _request<T>(
    String method,
    String key, {
    Map<String, String> query = const {},
    Object? data,
    String? payloadHash,
    Map<String, String> headers = const {},
    ResponseType? responseType,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final uri = _buildUri(key, query);
    final hash = payloadHash ?? _emptyPayloadHash;
    final signedHeaders = _signer.sign(
      method: method,
      uri: uri,
      dateTime: DateTime.now().toUtc(),
      payloadHash: hash,
      headers: headers,
    );
    return _dio.requestUri<T>(
      uri,
      data: data,
      options: Options(
        method: method,
        headers: signedHeaders,
        responseType: responseType,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  Uri _buildUri(String key, Map<String, String> query) {
    final endpointSegments = _endpoint.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final keySegments = _normalizeKey(
      key,
    ).split('/').where((segment) => segment.isNotEmpty).toList();
    final trailingSlash = key.endsWith('/') && keySegments.isNotEmpty;
    final pathSegments = <String>[
      ...endpointSegments,
      if (config.s3UsePathStyle) config.s3Bucket,
      ...keySegments,
      if (trailingSlash) '',
    ];
    final host = config.s3UsePathStyle
        ? _endpoint.host
        : '${config.s3Bucket}.${_endpoint.host}';
    return Uri(
      scheme: _endpoint.scheme,
      userInfo: _endpoint.userInfo,
      host: host,
      port: _endpoint.hasPort ? _endpoint.port : null,
      pathSegments: pathSegments,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  static String _normalizeKey(String key) {
    var normalized = key.replaceAll('\\', '/');
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  static String _directoryPrefix(String value) {
    final normalized = _normalizeKey(value);
    if (normalized.isEmpty) return '';
    return normalized.endsWith('/') ? normalized : '$normalized/';
  }

  static String _basename(String key) {
    final index = key.lastIndexOf('/');
    return index < 0 ? key : key.substring(index + 1);
  }

  static String? _childText(XmlElement parent, String localName) {
    return parent.children
        .whereType<XmlElement>()
        .where((element) => element.name.local == localName)
        .map((element) => element.innerText)
        .firstOrNull;
  }

  static DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return null;
    }
  }

  static String _xmlEscape(String value) => const HtmlEscape(
    HtmlEscapeMode.element,
  ).convert(value).replaceAll('&#39;', '&apos;');
}

class _S3ListPage {
  final List<S3ObjectInfo> objects;
  final List<String> prefixes;
  final String? nextContinuationToken;

  const _S3ListPage({
    required this.objects,
    required this.prefixes,
    this.nextContinuationToken,
  });
}

class _CompletedPart {
  final int number;
  final String etag;

  const _CompletedPart(this.number, this.etag);
}
