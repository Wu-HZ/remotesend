import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/models/server_endpoint.dart';
import 'package:remote_send/providers/text_endpoint_provider.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/message_history_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/screens/text_bridge_screen.dart';
import 'package:remote_send/services/text_clipboard_service.dart';
import 'package:remote_send/services/webdav_service.dart';

class _Clipboard extends TextClipboardService {
  String text = 'old clipboard';

  @override
  Future<String?> readText() async => text;
}

class _History extends MessageHistoryNotifier {
  _History(Ref ref) : super(WebDavService(), ref);
  final sent = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> sendMessage(String content) async {
    sent.add(content);
    return true;
  }
}

class _Connection extends ConnectionNotifier {
  _Connection() : super(WebDavService()) {
    state = const ConnectionStatus(state: WebDavConnectionState.connected);
  }
}

final _active = StateProvider<bool>((ref) => true);
final _server = StateProvider<ServerConfig?>((ref) => null);
const _toggle = ValueKey('clipboard-auto-send-toggle');
const _tick = Duration(milliseconds: 500);

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Clipboard clipboard, {
  bool configured = true,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isTextConfiguredProvider.overrideWithValue(configured),
        activeTextServerProvider.overrideWith((ref) => ref.watch(_server)),
        activeTextEndpointProvider.overrideWith(
          (ref) => WebDavEndpoint(
            ref.watch(_server) ??
                ServerConfig.create(
                  name: 'test',
                  serverUrl: 'https://example.invalid',
                  username: 'u',
                  password: 'p',
                ),
          ),
        ),
        textClipboardServiceProvider.overrideWithValue(clipboard),
        textConnectionStatusProvider.overrideWith((ref) => _Connection()),
        messageHistoryProvider.overrideWith((ref) => _History(ref)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, child) =>
              TextBridgeScreen(isActive: ref.watch(_active)),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(TextBridgeScreen)),
  );
}

void main() {
  testWidgets(
    'toggle sends new copies, preserves drafts and can stop immediately',
    (tester) async {
      final clipboard = _Clipboard();
      final container = await _mount(tester, clipboard);
      final history =
          container.read(messageHistoryProvider.notifier) as _History;
      expect(
        tester.widget<IconButton>(find.byKey(_toggle)).isSelected,
        isFalse,
      );
      await tester.enterText(find.byType(TextField), 'keep this draft');
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      expect(tester.widget<IconButton>(find.byKey(_toggle)).isSelected, isTrue);
      expect(find.text('Auto-sending · Click to stop'), findsOneWidget);
      await tester.pump(_tick);
      expect(history.sent, isEmpty);
      clipboard.text = 'copied externally';
      await tester.pump(_tick);
      expect(history.sent, ['copied externally']);
      expect(find.text('keep this draft'), findsOneWidget);
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      clipboard.text = 'not sent';
      await tester.pump(_tick);
      expect(history.sent, ['copied externally']);
      expect(
        tester.widget<IconButton>(find.byKey(_toggle)).isSelected,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('leaving the text tab stops and returning does not re-enable', (
    tester,
  ) async {
    final clipboard = _Clipboard();
    final container = await _mount(tester, clipboard);
    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    container.read(_active.notifier).state = false;
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(_toggle)).isSelected, isFalse);
    clipboard.text = 'other tab';
    await tester.pump(_tick);
    container.read(_active.notifier).state = true;
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(_toggle)).isSelected, isFalse);
    expect(
      (container.read(messageHistoryProvider.notifier) as _History).sent,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disconnecting stops the session', (tester) async {
    final container = await _mount(tester, _Clipboard());
    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    container.read(textConnectionStatusProvider.notifier).reset();
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(_toggle)).isSelected, isFalse);
    expect(tester.widget<IconButton>(find.byKey(_toggle)).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'switching servers stops the session instead of changing its destination',
    (tester) async {
      final container = await _mount(tester, _Clipboard());
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      container.read(_server.notifier).state = ServerConfig.create(
        name: 'Other server',
        serverUrl: 'https://example.com',
        username: 'user',
        password: 'password',
      );
      await tester.pump();
      expect(
        tester.widget<IconButton>(find.byKey(_toggle)).isSelected,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the additional control fits a narrow phone screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Isolate the input controls from the pre-existing connected app-bar layout.
    await _mount(tester, _Clipboard(), configured: false);
    expect(find.byKey(_toggle), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
