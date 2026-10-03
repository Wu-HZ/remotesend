import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/download_path_provider.dart';
import 'package:remote_send/screens/settings_screen.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/download_path_service.dart';

class _Config extends ConfigNotifier {
  _Config() : super(ConfigService()) {
    state = AsyncData(AppConfig());
  }

  @override
  Future<bool> updateConfig(AppConfig config) async {
    state = AsyncData(config);
    return true;
  }
}

void main() {
  testWidgets(
    'Gotify dialog can close after focusing a field without disposing its controller early',
    (tester) async {
      final config = _Config();
      tester.view.physicalSize = const Size(1264, 2780);
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
      final gotifyButton = find.text('Gotify 连接');
      await tester.ensureVisible(gotifyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('已关闭'));
      await tester.pumpAndSettle();

      final urlField = find.byType(TextFormField).first;
      await tester.tap(urlField);
      await tester.pump();
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextFormField), findsNothing);

      // Reopening and saving still reads the latest values from all three fields.
      await tester.tap(find.text('已关闭'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'https://gotify.example.com');
      await tester.enterText(fields.at(1), 'app-token');
      await tester.enterText(fields.at(2), 'client-token');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        config.debugState.valueOrNull?.gotify.serverUrl,
        'https://gotify.example.com',
      );
      expect(config.debugState.valueOrNull?.gotify.appToken, 'app-token');
      expect(config.debugState.valueOrNull?.gotify.clientToken, 'client-token');
    },
  );
}
