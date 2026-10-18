import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/providers/camera_capture_provider.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/download_path_provider.dart';
import 'package:remote_send/providers/gotify_coordinator_provider.dart';
import 'package:remote_send/providers/opened_file_provider.dart';
import 'package:remote_send/providers/pending_upload_provider.dart';
import 'package:remote_send/providers/upload_queue_provider.dart';
import 'package:remote_send/screens/home_screen.dart';
import 'package:remote_send/screens/pending_upload_screen.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/download_path_service.dart';
import 'package:remote_send/services/opened_file_service.dart';

class _Config extends ConfigNotifier {
  _Config() : super(ConfigService()) {
    final server = ServerConfig.create(
      name: 'Test server',
      serverUrl: 'https://example.invalid',
      username: 'u',
      password: 'p',
    );
    state = AsyncData(
      AppConfig(
        servers: [server],
        activeFilesServerId: server.id,
        activeTextServerId: server.id,
        dragMode: 'instant',
      ),
    );
  }
}

class _Coordinator extends StateNotifier<GotifyCoordinatorState>
    implements GotifyCoordinatorNotifier {
  _Coordinator() : super(const GotifyCoordinatorState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends DownloadPathService {
  @override
  Future<String> rootPath(String configuredDirectory) async => '/downloads';
}

class _Service extends OpenedFileService {
  final controller = StreamController<OpenedFileEvent>.broadcast(sync: true);
  @override
  Stream<OpenedFileEvent> get events => controller.stream;
}

void main() {
  testWidgets(
    'opening a file navigates to pending even when normal sharing sends instantly',
    (tester) async {
      final service = _Service();
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('opened_file_ui_'),
      );
      final file = await tester.runAsync(
        () => File('${root!.path}/report.pdf').writeAsString('file'),
      );
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith((ref) => _Config()),
          cameraSupportedProvider.overrideWithValue(false),
          gotifyCoordinatorProvider.overrideWith((ref) => _Coordinator()),
          downloadPathServiceProvider.overrideWithValue(_Paths()),
          openedFileSupportedProvider.overrideWithValue(true),
          openedFileServiceProvider.overrideWithValue(service),
        ],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const HomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(container.read(selectedTabProvider), 0);
        container.read(openedFileProvider.notifier).initialize();
        service.controller.add(OpenedFileEvent(id: 'file', path: file!.path));
        await tester.pumpAndSettle();
        expect(container.read(selectedTabProvider), 1);
        expect(find.byType(PendingUploadScreen), findsOneWidget);
        expect(find.byTooltip('report.pdf'), findsOneWidget);
        expect(container.read(pendingUploadProvider).filePaths, [file.path]);
        expect(container.read(uploadQueueProvider).items, isEmpty);

        service.controller.add(
          const OpenedFileEvent(
            id: 'denied',
            error: OpenedFileError.permissionDenied,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Cannot read this file'), findsOneWidget);
        expect(container.read(pendingUploadProvider).filePaths, [file.path]);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await service.controller.close();
        await tester.runAsync(() => root!.delete(recursive: true));
      }
    },
  );
}
