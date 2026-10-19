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

      final urlField = find.byKey(const ValueKey('gotify-server-url'));
      await tester.tap(urlField);
      await tester.pump();
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextFormField), findsNothing);

      // Reopening and saving reads current values by field identity, not order.
      await tester.tap(find.text('已关闭'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gotify-server-emoji')),
        '⚡',
      );
      await tester.enterText(urlField, 'https://gotify.example.com');
      await tester.enterText(
        find.byKey(const ValueKey('gotify-app-token')),
        'app-token',
      );
      await tester.enterText(
        find.byKey(const ValueKey('gotify-client-token')),
        'client-token',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final saved = config.state.requireValue.gotify;
      expect(saved.serverUrl, 'https://gotify.example.com');
      expect(saved.emoji, '⚡');
      expect(saved.appToken, 'app-token');
      expect(saved.clientToken, 'client-token');
    },
  );
}
