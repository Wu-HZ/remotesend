import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/services/webdav_exceptions.dart';
import 'package:remote_send/services/webdav_service.dart';

class _Service extends WebDavService {
  String? listedPath;
  WebDavResult<List<RemoteFile>> result = const WebDavResult.success([]);

  @override
  Future<WebDavResult<List<RemoteFile>>> listFiles([String? subPath]) async {
    listedPath = subPath;
    return result;
  }
}

void main() {
  test(
    'file info uses the same full metadata and path as the root listing',
    () async {
      final file = RemoteFile(
        name: 'report.txt',
        path: '/RemoteSend/Files/report.txt',
        size: 4,
        eTag: '"version-1"',
        modifiedTime: DateTime.utc(2026, 9, 1),
        isDirectory: false,
      );
      final service = _Service()..result = WebDavResult.success([file]);
      final result = await service.readFileInfo('report.txt');
      expect(result.data, same(file));
      expect(service.listedPath, isNull);
    },
  );

  test(
    'nested unicode paths resolve against their own parent folder',
    () async {
      const file = RemoteFile(
        name: '报告 1.txt',
        path: '/RemoteSend/Files/资料/报告 1.txt',
        size: 4,
        eTag: '"nested-version"',
        isDirectory: false,
      );
      final service = _Service()..result = const WebDavResult.success([file]);
      final result = await service.readFileInfo('资料/报告 1.txt');
      expect(service.listedPath, '资料');
      expect(result.data, same(file));
    },
  );

  test(
    'missing files and same-name directories are not cached as files',
    () async {
      final service = _Service()
        ..result = const WebDavResult.success([
          RemoteFile(
            name: 'report.txt',
            path: '/report.txt/',
            isDirectory: true,
          ),
        ]);
      final result = await service.readFileInfo('report.txt');
      expect(result.isFailure, isTrue);
      expect(result.error, isA<WebDavNotFoundException>());
    },
  );

  test(
    'metadata read failures are preserved instead of inventing a version',
    () async {
      const error = WebDavConnectionException(message: 'Offline');
      final service = _Service()..result = const WebDavResult.failure(error);
      final result = await service.readFileInfo('report.txt');
      expect(result.isFailure, isTrue);
      expect(result.error, same(error));
    },
  );
}
