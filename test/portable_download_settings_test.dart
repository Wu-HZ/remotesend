import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/download_path_provider.dart';
import 'package:remote_send/screens/settings_screen.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/download_path_service.dart';

class _RecordingPicker extends FilePicker {
  String? lastInitialDirectory;
  bool? lastLockParentWindow;
  bool fail = false;
  String? nextResult;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    lastInitialDirectory = initialDirectory;
    lastLockParentWindow = lockParentWindow;
    if (fail) throw StateError('picker failed');
    return nextResult; // Null means cancelled; the current mode is preserved.
  }
}

class _Config extends ConfigNotifier {
  _Config([AppConfig? initial]) : super(ConfigService()) {
    state = AsyncData(initial ?? AppConfig());
  }

  AppConfig get config => state.valueOrNull!;

  @override
  Future<bool> updateConfig(AppConfig config) async {
    state = AsyncData(config);
    return true;
  }
}

void main() {
  testWidgets(
    'download location choices preserve system, portable and custom modes',
    (tester) async {
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
      final config = _Config();
      final root = Directory.systemTemp.createTempSync('portable_picker_');
      addTearDown(() => root.deleteSync(recursive: true));
      final appDirectory = Directory(p.join(root.path, 'USB'));
      appDirectory.createSync();
      final portable = DownloadPathService(
        defaultDirectory: () async => root,
        executablePath: () => p.join(appDirectory.path, 'RemoteSend.exe'),
      );
      if (Platform.isWindows) {
        FilePicker.platform = FilePickerWindows();
      } else if (Platform.isLinux) {
        FilePicker.platform = FilePickerLinux();
      } else {
        FilePicker.platform = FilePickerMacOS();
      }
      final originalPicker = FilePicker.platform;
      final picker = _RecordingPicker();
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = originalPicker);
      tester.view.physicalSize = const Size(1264, 4300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith((ref) => config),
            downloadPathServiceProvider.overrideWithValue(portable),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('en'), Locale('zh')],
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(config.config.downloadLocation, '');
      await tester.tap(find.text('系统下载文件夹（默认）'));
      await tester.pumpAndSettle();
      final system = find.byKey(const ValueKey('download-mode-system'));
      final app = find.byKey(const ValueKey('download-mode-portable'));
      final custom = find.byKey(const ValueKey('download-mode-custom'));
      expect(find.text('系统下载文件夹（默认）'), findsNWidgets(2));
      expect(find.text(root.path), findsWidgets);

      await tester.tap(app);
      await tester.pumpAndSettle();
      expect(
        config.config.downloadLocation,
        DownloadPathService.portableDownloadsLocation,
      );
      expect(
        await portable.rootPath(config.config.downloadLocation),
        p.join(appDirectory.path, 'Downloads'),
      );
      await tester.tap(find.text('程序旁的 Downloads（适合 U 盘）').first);
      await tester.pumpAndSettle();
      expect(find.text('请同时启用便携模式，让此设置随程序一起移动。'), findsOneWidget);

      // A new portable Downloads folder does not exist yet. Cancelling the
      // custom picker must leave the portable selection unchanged.
      await tester.tap(custom);
      await tester.pumpAndSettle();
      expect(picker.lastInitialDirectory, appDirectory.path);
      expect(picker.lastLockParentWindow, Platform.isWindows);
      expect(
        config.config.downloadLocation,
        DownloadPathService.portableDownloadsLocation,
      );

      final downloads = Directory(p.join(appDirectory.path, 'Downloads'));
      downloads.createSync();
      await tester.tap(find.text('程序旁的 Downloads（适合 U 盘）').first);
      await tester.pumpAndSettle();
      await tester.tap(custom);
      await tester.pumpAndSettle();
      expect(picker.lastInitialDirectory, downloads.path);

      final chosen = Directory(p.join(root.path, 'chosen'))..createSync();
      picker.nextResult = chosen.path;
      await tester.tap(find.text('程序旁的 Downloads（适合 U 盘）').first);
      await tester.pumpAndSettle();
      await tester.tap(custom);
      await tester.pumpAndSettle();
      expect(config.config.downloadLocation, chosen.path);
      await tester.tap(find.text('自定义文件夹'));
      await tester.pumpAndSettle();
      expect(find.text(chosen.path), findsWidgets);
      expect(
        find.descendant(of: custom, matching: find.text('选择下载位置')),
        findsOneWidget,
      );

      picker.fail = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择下载位置'));
      await tester.pumpAndSettle();
      // The previous successful save's snackbar must finish before this error
      // snackbar becomes visible.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('picker failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(config.config.downloadLocation, chosen.path);

      await tester.tap(find.text('自定义文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(system);
      await tester.pumpAndSettle();
      expect(config.config.downloadLocation, '');
    },
  );

  testWidgets('download choices fit the narrow desktop window', (tester) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    final config = _Config(
      AppConfig(
        downloadLocation: DownloadPathService.portableDownloadsLocation,
        portableMode: true,
      ),
    );
    tester.view.physicalSize = const Size(420, 630);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWith((ref) => config),
          downloadPathServiceProvider.overrideWithValue(
            DownloadPathService(
              defaultDirectory: () async => Directory.systemTemp,
              executablePath: () =>
                  p.join(Directory.systemTemp.path, 'USB', 'RemoteSend.exe'),
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: [Locale('en'), Locale('zh')],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('自动下载'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('下载位置'), findsOneWidget);
  });
}
