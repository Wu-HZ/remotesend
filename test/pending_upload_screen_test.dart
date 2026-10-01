import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/providers/camera_capture_provider.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/pending_upload_provider.dart';
import 'package:remote_send/providers/upload_queue_provider.dart';
import 'package:remote_send/screens/pending_upload_screen.dart';
import 'package:remote_send/services/camera_capture_service.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/webdav_service.dart';

class _Config extends ConfigNotifier {
  _Config(AppConfig config) : super(ConfigService()) {
    state = AsyncData(config);
  }
}

class _Camera extends CameraCaptureService {
  final String path;
  _Camera(this.path);

  @override
  Future<String?> capture() async => path;

  @override
  Future<List<String>> recover() async => [];

  @override
  Future<void> cleanExpired(Set<String> Function() protectedPaths) async {}
}

class _Queue extends UploadQueueNotifier {
  final Ref ref;
  final batches = <List<String>>[];
  final entered = Completer<void>();
  Completer<void>? gate;
  bool fail = false;
  bool returnToPending = false;

  _Queue(this.ref) : super(WebDavService(), ref);

  @override
  Future<void> addFiles(
    List<String> localPaths, {
    String? remoteBasePath,
  }) async {
    batches.add(List.of(localPaths));
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (fail) throw const FileSystemException('test failure');
    if (returnToPending) {
      ref.read(pendingUploadProvider.notifier).addFiles(localPaths);
    }
  }
}

void main() {
  late Directory root;
  late File photo;
  late ProviderContainer container;
  late _Queue queue;
  final server = ServerConfig(
    id: 'test-server',
    name: '测试服务器',
    serverUrl: 'https://example.invalid',
    username: 'test',
    password: 'test',
    createdAt: DateTime(2026),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pending_upload_widget_');
    photo = File(p.join(root.path, 'photo.png'));
    await photo.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      ),
    );
    container = ProviderContainer(
      overrides: [
        cameraSupportedProvider.overrideWithValue(true),
        cameraCaptureServiceProvider.overrideWithValue(_Camera(photo.path)),
        configProvider.overrideWith(
          (ref) => _Config(
            AppConfig(servers: [server], activeFilesServerId: server.id),
          ),
        ),
        uploadQueueProvider.overrideWith((ref) => queue = _Queue(ref)),
      ],
    );
    queue = container.read(uploadQueueProvider.notifier) as _Queue;
    container.read(pendingUploadProvider.notifier).addFiles([photo.path]);
  });

  tearDown(() async {
    container.dispose();
    // Windows 上等待缩略图和文件统计释放句柄。
    for (var attempt = 0; ; attempt++) {
      try {
        await root.delete(recursive: true);
        break;
      } on PathAccessException {
        if (attempt == 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  Future<void> show(WidgetTester tester, {ProviderContainer? scope}) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() async {
      await precacheImage(
        ResizeImage.resizeIfNeeded(144, null, FileImage(photo)),
        tester.element(find.byType(SizedBox).first),
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope ?? container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PendingUploadScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('窄屏显示继续拍照和添加文件，照片可以预览', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester);
    expect(find.text('继续拍照'), findsOneWidget);
    expect(find.text('添加文件'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(queue.batches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('继续拍照只追加到列表，不开始上传', (tester) async {
    container.read(pendingUploadProvider.notifier).clear();
    await show(tester);
    await tester.tap(find.text('继续拍照'));
    await tester.pumpAndSettle();
    expect(container.read(pendingUploadProvider).filePaths, [photo.path]);
    expect(queue.batches, isEmpty);
  });

  testWidgets('桌面端隐藏相机入口', (tester) async {
    final desktop = ProviderContainer(
      overrides: [cameraSupportedProvider.overrideWithValue(false)],
    );
    addTearDown(desktop.dispose);
    await show(tester, scope: desktop);
    expect(find.text('继续拍照'), findsNothing);
    expect(find.text('添加文件'), findsOneWidget);
  });

  testWidgets('发送交接中禁用操作，保留新追加与失败回退的文件', (tester) async {
    queue.gate = Completer<void>();
    queue.returnToPending = true;
    await show(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('上传到服务器'));
      await queue.entered.future;
    });
    await tester.pump();
    expect(container.read(pendingUploadProvider).isSubmitting, isTrue);
    final send = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '上传到服务器',
      ),
    );
    expect(send.onPressed, isNull);
    container.read(pendingUploadProvider.notifier).addFiles(['new.txt']);
    queue.gate!.complete();
    await tester.pumpAndSettle();
    expect(queue.batches, [
      [photo.path],
    ]);
    expect(container.read(pendingUploadProvider).filePaths, [
      'new.txt',
      photo.path,
    ]);
    expect(container.read(pendingUploadProvider).isSubmitting, isFalse);
  });

  testWidgets('队列接收失败时恢复待发送照片', (tester) async {
    queue.fail = true;
    await show(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('上传到服务器'));
      await queue.entered.future;
    });
    await tester.pumpAndSettle();
    expect(container.read(pendingUploadProvider).filePaths, [photo.path]);
    expect(container.read(pendingUploadProvider).isSubmitting, isFalse);
  });
}
