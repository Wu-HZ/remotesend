import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/download_path_provider.dart';
import 'package:remote_send/screens/settings_screen.dart';
import 'package:remote_send/screens/transfer_queue_screen.dart';
import 'package:remote_send/services/android_folder_opener_service.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/download_path_service.dart';

class _Config extends ConfigNotifier {
  _Config(AppConfig config) : super(ConfigService()) {
    state = AsyncData(config);
  }

  AppConfig get config => state.requireValue;

  @override
  Future<bool> updateConfig(AppConfig config) async {
    state = AsyncData(config);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('remote_send/folder_opener');
  final calls = <MethodCall>[];
  bool canOpen = true;
  final mtIcon = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN4HGTyHwAF7gJparMppwAAAABJRU5ErkJggg==',
    ),
  );
  final choices = <Map<String, Object?>>[
    {
      'component': 'bin.mt.plus/bin.mt.plus.MainActivity',
      'label': 'MT 管理器',
      'icon': mtIcon,
    },
    {
      'component': 'bin.mt.plus.canary/bin.mt.plus.canary.MainActivity',
      'label': 'MT 管理器测试版',
      'icon': null,
    },
  ];

  setUp(() {
    calls.clear();
    canOpen = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'available') return choices;
          if (call.method == 'open') return canOpen;
          throw MissingPluginException();
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'selection survives JSON, copies, and restoring older configurations',
    () {
      expect(
        AppConfig.fromJson({
          'version': 14,
          'servers': [],
        }).androidFolderOpenerComponent,
        '',
      );
      const component = 'bin.mt.plus/bin.mt.plus.MainActivity';
      final selected = AppConfig().copyWith(
        androidFolderOpenerComponent: component,
        androidFolderOpenerLabel: 'MT 管理器',
      );
      final restored = AppConfig.fromJsonString(selected.toJsonString());
      expect(restored.androidFolderOpenerComponent, component);
      expect(restored.androidFolderOpenerLabel, 'MT 管理器');
      expect(restored, selected);
      expect(restored.hashCode, selected.hashCode);
      expect(
        restored
            .copyWithNullActiveServers(clearFiles: true)
            .androidFolderOpenerComponent,
        component,
      );
      expect(
        restored
            .copyWith(
              androidFolderOpenerComponent: '',
              androidFolderOpenerLabel: '',
            )
            .androidFolderOpenerComponent,
        '',
      );
    },
  );

  test(
    'Android service lists candidates and opens the exact selected activity',
    () async {
      const service = AndroidFolderOpenerService();
      final apps = await service.available('/storage/emulated/0/Download');
      expect(apps.map((app) => app.label), ['MT 管理器', 'MT 管理器测试版']);
      expect(apps.first.iconPng, orderedEquals(mtIcon));
      expect(apps.last.iconPng, isNull);
      expect(calls.single.method, 'available');
      expect(calls.single.arguments, {'path': '/storage/emulated/0/Download'});

      await service.open('/storage/emulated/0/Download', apps.first.component);
      expect(calls.last.method, 'open');
      expect(calls.last.arguments, {
        'path': '/storage/emulated/0/Download',
        'component': 'bin.mt.plus/bin.mt.plus.MainActivity',
      });

      canOpen = false;
      await expectLater(
        service.open('/storage/emulated/0/Download', apps.first.component),
        throwsA(isA<SelectedFolderOpenerUnavailable>()),
      );
    },
  );

  test('configured folder opener bypasses the system chooser', () async {
    final config = _Config(
      AppConfig(
        androidFolderOpenerComponent: 'bin.mt.plus/bin.mt.plus.MainActivity',
        androidFolderOpenerLabel: 'MT 管理器',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        configProvider.overrideWith((ref) => config),
        androidFolderOpenerSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    final opener = container.read(openLocalDirectoryProvider);
    expect(await opener('/storage/emulated/0/Download'), isTrue);
    expect(calls.map((call) => call.method), ['open']);
    canOpen = false;
    await expectLater(
      opener('/storage/emulated/0/Download'),
      throwsA(isA<SelectedFolderOpenerUnavailable>()),
    );
    // Do not silently forget the choice or launch another app on failure.
    expect(config.config.androidFolderOpenerLabel, 'MT 管理器');
    expect(calls.length, 2);
  });

  testWidgets('transfer queue opens the configured Android app directly', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('folder_opener_queue_');
    addTearDown(() => root.deleteSync(recursive: true));
    final config = _Config(
      AppConfig(
        downloadLocation: root.path,
        androidFolderOpenerComponent: choices.first['component'] as String,
        androidFolderOpenerLabel: 'MT 管理器',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        configProvider.overrideWith((ref) => config),
        androidFolderOpenerSupportedProvider.overrideWithValue(true),
        downloadPathServiceProvider.overrideWithValue(
          DownloadPathService(defaultDirectory: () async => root),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TransferQueueScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开下载文件夹'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'open');
    expect(calls.single.arguments, {
      'path': root.path,
      'component': choices.first['component'],
    });
  });

  testWidgets('Android download settings remember MT Manager until reset', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('folder_opener_');
    addTearDown(() => root.deleteSync(recursive: true));
    final config = _Config(AppConfig(downloadLocation: root.path));
    final container = ProviderContainer(
      overrides: [
        configProvider.overrideWith((ref) => config),
        androidFolderOpenerSupportedProvider.overrideWithValue(true),
        downloadPathServiceProvider.overrideWithValue(
          DownloadPathService(defaultDirectory: () async => root),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1060, 3100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('android-folder-opener-setting')),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    final setting = find.byKey(const ValueKey('android-folder-opener-setting'));
    await tester.tap(
      find.descendant(of: setting, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'path': root.path});
    final iconFinder = find.byKey(
      const ValueKey(
        'android-folder-icon-bin.mt.plus/bin.mt.plus.MainActivity',
      ),
    );
    expect(iconFinder, findsOneWidget);
    final icon = tester.widget<Image>(iconFinder).image as MemoryImage;
    expect(icon.bytes, orderedEquals(mtIcon));
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'android-folder-opener-bin.mt.plus/bin.mt.plus.MainActivity',
          ),
        ),
        matching: find.byIcon(Icons.apps),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'android-folder-opener-bin.mt.plus.canary/bin.mt.plus.canary.MainActivity',
          ),
        ),
        matching: find.byIcon(Icons.apps),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'android-folder-opener-bin.mt.plus/bin.mt.plus.MainActivity',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      config.config.androidFolderOpenerComponent,
      choices.first['component'],
    );
    expect(find.text('MT 管理器'), findsWidgets);

    await tester.tap(
      find.descendant(of: setting, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('android-folder-opener-system')),
    );
    await tester.pumpAndSettle();
    expect(config.config.androidFolderOpenerComponent, '');
    expect(config.config.androidFolderOpenerLabel, '');
    expect(find.text('系统选择（默认）'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
