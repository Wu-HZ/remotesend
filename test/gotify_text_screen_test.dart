import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/app_config.dart';
import 'package:remote_send/models/gotify_models.dart';
import 'package:remote_send/models/gotify_text_message.dart';
import 'package:remote_send/models/server_config.dart';
import 'package:remote_send/models/server_endpoint.dart';
import 'package:remote_send/providers/camera_capture_provider.dart';
import 'package:remote_send/providers/config_provider.dart';
import 'package:remote_send/providers/download_path_provider.dart';
import 'package:remote_send/providers/gotify_coordinator_provider.dart';
import 'package:remote_send/providers/gotify_provider.dart';
import 'package:remote_send/providers/gotify_text_session_provider.dart';
import 'package:remote_send/providers/message_history_provider.dart';
import 'package:remote_send/providers/text_send_provider.dart';
import 'package:remote_send/providers/webdav_provider.dart';
import 'package:remote_send/screens/text_bridge_screen.dart';
import 'package:remote_send/screens/settings_screen.dart';
import 'package:remote_send/screens/home_screen.dart';
import 'package:remote_send/services/webdav_service.dart';
import 'package:remote_send/services/config_service.dart';
import 'package:remote_send/services/download_path_service.dart';
import 'package:remote_send/services/text_clipboard_service.dart';
import 'package:remote_send/widgets/text_endpoint_selector.dart';

class _Store extends ConfigService {
  AppConfig? saved;
  @override
  Future<bool> saveConfig(AppConfig config) async {
    saved = config;
    return true;
  }
}

class _Config extends ConfigNotifier {
  _Config({bool webDav = false, _Store? store}) : super(store ?? _Store()) {
    final server = ServerConfig.create(
      name: 'WebDAV',
      serverUrl: 'https://example.invalid',
      username: 'u',
      password: 'p',
    );
    state = AsyncData(
      AppConfig(
        servers: webDav ? [server] : [],
        activeTextServerId: gotifyTextServerId,
        gotify: GotifyConfig(
          enabled: true,
          registerAsTextServer: true,
          serverUrl: 'https://gotify.invalid',
          appToken: 'app',
          clientToken: 'client',
          deviceId: 'local',
        ),
      ),
    );
  }
}

class _Gotify extends StateNotifier<GotifyState> implements GotifyNotifier {
  _Gotify()
    : super(
        const GotifyState(
          status: GotifyConnectionStatus.connected,
          applicationId: 7,
        ),
      );
  final sent = <RemoteSendEvent>[];
  bool fail = false;
  @override
  Future<void> sendRealtimeText(RemoteSendEvent event) async {
    sent.add(event);
    if (fail) throw const RealtimeTextException(RealtimeTextFailure.sendFailed);
  }

  void disconnect() =>
      state = const GotifyState(status: GotifyConnectionStatus.reconnecting);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Coordinator extends StateNotifier<GotifyCoordinatorState>
    implements GotifyCoordinatorNotifier {
  _Coordinator() : super(const GotifyCoordinatorState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clipboard extends TextClipboardService {
  String text = 'initial';
  @override
  Future<String?> readText() async => text;
  @override
  Future<void> writeText(String text) async {
    this.text = text;
  }
}

class _Paths extends DownloadPathService {
  @override
  Future<String> rootPath(String configuredDirectory) async => '/downloads';
}

final _active = StateProvider<bool>((ref) => true);
const _previewFont = String.fromEnvironment('UI_PREVIEW_FONT');
const _previewIcons = String.fromEnvironment('UI_PREVIEW_ICONS');
const _previewBoundary = ValueKey('ui-preview-boundary');

Future<void> _captureUi(WidgetTester tester, String name) async {
  if (_previewFont.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewBoundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('build/ui-previews/$name.png').parent.create(recursive: true);
    await File(
      'build/ui-previews/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _Harness {
  _Harness({bool settings = false, bool home = false}) {
    config = _Config(webDav: settings, store: store);
    container = ProviderContainer(
      overrides: [
        configProvider.overrideWith((ref) => config),
        gotifyProvider.overrideWith((ref) => gotify),
        gotifyCoordinatorProvider.overrideWith((ref) => _Coordinator()),
        textClipboardServiceProvider.overrideWithValue(clipboard),
        cameraSupportedProvider.overrideWithValue(false),
        downloadPathServiceProvider.overrideWithValue(_Paths()),
        if (!settings) ...[
          if (!home)
            webDavTextServiceProvider.overrideWith(
              (ref) =>
                  throw StateError('Gotify must not initialize WebDAV text'),
            )
          else
            webDavTextServiceProvider.overrideWithValue(WebDavService()),
          messageHistoryProvider.overrideWith(
            (ref) => throw StateError('Gotify must not load text history'),
          ),
          selectedDateProvider.overrideWith(
            (ref) =>
                throw StateError('Gotify must not initialize date selection'),
          ),
        ],
      ],
    );
  }
  late final _Config config;
  final store = _Store();
  final gotify = _Gotify();
  final clipboard = _Clipboard();
  late final ProviderContainer container;
  Future<void> mount(
    WidgetTester tester, {
    bool settings = false,
    bool home = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (_previewFont.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('UI preview')
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(_previewFont).readAsBytes()),
            ),
          );
        await loader.load();
        if (_previewIcons.isNotEmpty) {
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(_previewIcons).readAsBytes()),
              ),
            );
          await icons.load();
        }
      });
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: _previewBoundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(AppConfig.defaultPrimaryColor),
              ),
              fontFamily: _previewFont.isEmpty ? null : 'UI preview',
            ),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: settings
                ? const SettingsScreen()
                : home
                ? const HomeScreen()
                : Consumer(
                    builder: (context, ref, _) =>
                        TextBridgeScreen(isActive: ref.watch(_active)),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }
}

void main() {
  testWidgets(
    'Gotify icon can be saved, cancelled and cleared without clearing the session',
    (tester) async {
      final h = _Harness(settings: true);
      final tile = find.byKey(
        const ValueKey('server-tile-$gotifyTextServerId'),
      );
      final emoji = find.byKey(const ValueKey('gotify-server-emoji'));
      Future<void> edit() async {
        await tester.longPress(tile);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }

      try {
        await h.mount(tester, settings: true);
        h.container
            .read(gotifyTextSessionProvider.notifier)
            .receive(
              RemoteSendEvent(
                type: RemoteSendEvent.textDirect,
                senderDeviceId: 'peer',
                senderName: 'Phone',
                payload: {
                  'contentType': 'text/plain',
                  'content': 'Keep the session when changing icons',
                },
              ),
            );
        await edit();
        expect(tester.widget<TextFormField>(emoji).initialValue, isEmpty);
        await tester.enterText(emoji, '🚀');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(h.config.state.requireValue.gotify.emoji, '🚀');
        expect(h.store.saved!.gotify.emoji, '🚀');
        expect(
          find.descendant(of: tile, matching: find.text('🚀')),
          findsOneWidget,
        );
        await edit();
        expect(tester.widget<TextFormField>(emoji).initialValue, '🚀');
        await tester.enterText(emoji, '💡');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(h.config.state.requireValue.gotify.emoji, '🚀');
        expect(h.store.saved!.gotify.emoji, '🚀');
        await h.mount(tester);
        final selector = find.byKey(const ValueKey('text-endpoint-selector'));
        expect(
          find.descendant(of: selector, matching: find.text('🚀')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(TextEndpointPanel),
            matching: find.text('🚀'),
          ),
          findsOneWidget,
        );
        await tester.tap(selector);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(PopupMenuItem<String>),
            matching: find.text('🚀'),
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await h.mount(tester, settings: true);
        await edit();
        await tester.enterText(emoji, '');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(h.store.saved!.gotify.emoji, isEmpty);
        expect(
          find.descendant(of: tile, matching: find.byIcon(Icons.cloud)),
          findsOneWidget,
        );
        expect(
          h.container.read(gotifyTextSessionProvider).messages.single.content,
          'Keep the session when changing icons',
        );
        expect(h.config.state.requireValue.servers.single.emoji, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'Gotify refresh stays visible and does nothing online or offline, without initializing history or dates',
    (tester) async {
      final h = _Harness();
      try {
        await h.mount(tester);
        h.container
            .read(gotifyTextSessionProvider.notifier)
            .receive(
              RemoteSendEvent(
                type: RemoteSendEvent.textDirect,
                senderDeviceId: 'peer',
                senderName: 'Phone',
                payload: {
                  'contentType': 'text/plain',
                  'content': 'Do not clear or reload',
                },
              ),
            );
        await tester.pumpAndSettle();
        final before = h.container.read(gotifyTextSessionProvider);
        final refresh = find.byKey(const ValueKey('text-refresh'));
        expect(find.byTooltip('Refresh'), findsOneWidget);
        expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(h.container.read(gotifyTextSessionProvider), same(before));
        h.gotify.disconnect();
        await tester.pumpAndSettle();
        expect(refresh, findsOneWidget);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(h.container.read(gotifyTextSessionProvider), same(before));
        expect(h.gotify.sent, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'registered Gotify uses the same server card, with only file capability disabled and no switch description',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      final h = _Harness(settings: true);
      try {
        await h.mount(tester, settings: true);
        final webDavId = h.config.state.requireValue.servers.single.id;
        final gotifyTile = find.byKey(
          const ValueKey('server-tile-$gotifyTextServerId'),
        );
        final webDavTile = find.byKey(ValueKey('server-tile-$webDavId'));
        final gotifyCard = tester.widget<Card>(gotifyTile);
        final webDavCard = tester.widget<Card>(webDavTile);
        expect(gotifyCard.margin, webDavCard.margin);
        expect(gotifyCard.shape, webDavCard.shape);
        expect(
          find.descendant(of: gotifyTile, matching: find.byType(ListTile)),
          findsNothing,
        );
        expect(
          find.descendant(of: gotifyTile, matching: find.text('Gotify')),
          findsOneWidget,
        );
        final files = find.byKey(
          const ValueKey('server-files-$gotifyTextServerId'),
        );
        expect(tester.widget<GestureDetector>(files).onTap, isNull);
        expect(
          tester
              .widget<Opacity>(
                find.descendant(of: files, matching: find.byType(Opacity)),
              )
              .opacity,
          0.4,
        );
        expect(
          tester
              .widget<GestureDetector>(
                find.byKey(ValueKey('server-files-$webDavId')),
              )
              .onTap,
          isNotNull,
        );
        expect(
          tester
              .widget<GestureDetector>(
                find.byKey(const ValueKey('server-text-$gotifyTextServerId')),
              )
              .onTap,
          isNotNull,
        );
        await _captureUi(tester, 'gotify-settings-servers');
        await tester.scrollUntilVisible(
          find.text('Register as a text server'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final registration = find.ancestor(
          of: find.text('Register as a text server'),
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_BooleanEntry',
          ),
        );
        await tester.ensureVisible(registration);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SettingsScreen)),
        )!;
        expect(find.text(l10n.gotifyRegisterTextHint), findsNothing);
        await _captureUi(tester, 'gotify-settings-switch');
        expect(tester.takeException(), isNull);
      } finally {
        await h.dispose(tester);
        await tester.binding.setSurfaceSize(null);
      }
    },
  );

  testWidgets('Gotify and WebDAV use identical top connection status layout', (
    tester,
  ) async {
    final h = _Harness(settings: true);
    try {
      await h.mount(tester, settings: true);
      final textStatus = find.byKey(const ValueKey('connection-status-text'));
      final fileStatus = find.byKey(const ValueKey('connection-status-files'));
      final gotify = tester.widget<Container>(textStatus);
      final files = tester.widget<Container>(fileStatus);
      expect(gotify.padding, files.padding);
      expect(
        (gotify.decoration as BoxDecoration).borderRadius,
        (files.decoration as BoxDecoration).borderRadius,
      );
      expect(
        find.descendant(of: textStatus, matching: find.byType(ListTile)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: textStatus,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: textStatus, matching: find.text('Gotify')),
        findsOneWidget,
      );
      final height = tester.getSize(textStatus).height;
      await h.config.updateConfig(
        h.config.state.requireValue.copyWith(
          activeTextServerId: h.config.state.requireValue.servers.single.id,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(textStatus).height, height);
      expect(tester.widget<Container>(textStatus).padding, gotify.padding);
      expect(
        (tester.widget<Container>(textStatus).decoration as BoxDecoration)
            .borderRadius,
        (gotify.decoration as BoxDecoration).borderRadius,
      );
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets(
    'Gotify reuses WebDAV composer and bubble styling with avatars and tap-to-copy',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      final h = _Harness();
      try {
        await h.mount(tester);
        final input = tester.widget<TextField>(
          find.byKey(const ValueKey('gotify-text-input')),
        );
        final border = input.decoration!.border! as OutlineInputBorder;
        expect(input.decoration!.filled, isTrue);
        expect(border.borderRadius, BorderRadius.circular(24));
        expect(border.borderSide, BorderSide.none);
        expect(
          input.decoration!.contentPadding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );
        expect(find.text('No messages yet'), findsOneWidget);
        expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TextBridgeScreen)),
        )!;
        expect(find.text(l10n.gotifySessionNotice), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('gotify-text-input')),
          'Same chat layout',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('gotify-text-send')));
        await tester.pumpAndSettle();
        final message = h.container
            .read(gotifyTextSessionProvider)
            .messages
            .single;
        final bubble = find.byKey(
          ValueKey('text-message-bubble-${message.id}'),
        );
        final box = tester.widget<Container>(
          find
              .descendant(
                of: bubble,
                matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration is BoxDecoration,
                ),
              )
              .first,
        );
        final colorScheme = Theme.of(tester.element(bubble)).colorScheme;
        expect((box.decoration as BoxDecoration).color, colorScheme.primary);
        expect(
          box.padding,
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        );
        expect(find.byType(CircleAvatar), findsOneWidget);
        expect(
          find.descendant(of: bubble, matching: find.byIcon(Icons.copy)),
          findsNothing,
        );
        h.container
            .read(gotifyTextSessionProvider.notifier)
            .receive(
              RemoteSendEvent(
                type: RemoteSendEvent.textDirect,
                senderDeviceId: 'phone',
                senderName: 'Phone',
                payload: {
                  'contentType': 'text/plain',
                  'content': 'Same incoming bubble',
                },
              ),
            );
        await tester.pumpAndSettle();
        expect(find.byType(CircleAvatar), findsNWidgets(2));
        await _captureUi(tester, 'gotify-text-unified');
        await tester.tap(bubble);
        await tester.pump();
        expect(h.clipboard.text, 'Same chat layout');
        expect(find.byKey(const ValueKey('text-date-picker')), findsNothing);
      } finally {
        await h.dispose(tester);
        await tester.binding.setSurfaceSize(null);
      }
    },
  );

  testWidgets(
    'registering Gotify does not auto-select it; a Gotify-only user can explicitly choose it',
    (tester) async {
      final h = _Harness();
      try {
        await h.config.updateConfig(
          h.config.state.requireValue.copyWithNullActiveServers(
            clearText: true,
          ),
        );
        await h.mount(tester);
        expect(h.config.state.requireValue.activeTextServerId, isNull);
        expect(find.byKey(const ValueKey('gotify-text-input')), findsNothing);
        await tester.tap(find.text('Gotify'));
        await tester.pumpAndSettle();
        expect(
          h.config.state.requireValue.activeTextServerId,
          gotifyTextServerId,
        );
        expect(find.byKey(const ValueKey('gotify-text-input')), findsOneWidget);
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'Gotify-only home remains usable and returning from files never refreshes WebDAV history',
    (tester) async {
      final h = _Harness(home: true);
      try {
        await h.mount(tester, home: true);
        expect(h.container.read(selectedTabProvider), 0);
        h.container
            .read(gotifyTextSessionProvider.notifier)
            .receive(
              RemoteSendEvent(
                type: RemoteSendEvent.textDirect,
                senderDeviceId: 'remote',
                senderName: 'Phone',
                payload: {
                  'contentType': 'text/plain',
                  'content': 'keep this session',
                },
              ),
            );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Files').first);
        await tester.pumpAndSettle();
        expect(h.container.read(selectedTabProvider), 1);
        await tester.tap(find.text('Text').first);
        await tester.pumpAndSettle();
        expect(h.container.read(selectedTabProvider), 0);
        expect(
          find.text('keep this session', findRichText: true),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('text-date-picker')), findsNothing);
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'Gotify-only page sends and receives without WebDAV, history or dates',
    (tester) async {
      final h = _Harness();
      try {
        await h.mount(tester);
        expect(find.byKey(const ValueKey('text-date-picker')), findsNothing);
        expect(find.byTooltip('Refresh'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('gotify-text-input')),
          'hello\n你好',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('gotify-text-send')));
        await tester.pumpAndSettle();
        expect(h.gotify.sent.single.payload['content'], 'hello\n你好');
        expect(find.byTooltip('Sent to Gotify'), findsOneWidget);
        expect(find.text('Sent to Gotify'), findsNothing);
        h.container
            .read(gotifyTextSessionProvider.notifier)
            .receive(
              RemoteSendEvent(
                type: RemoteSendEvent.textDirect,
                senderDeviceId: 'phone',
                senderName: 'Phone',
                payload: {'contentType': 'text/plain', 'content': 'received'},
              ),
            );
        await tester.pumpAndSettle();
        expect(find.text('received', findRichText: true), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('gotify-clear-session')));
        await tester.pumpAndSettle();
        expect(h.container.read(gotifyTextSessionProvider).messages, isEmpty);
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'clipboard paste and temporary auto-send share the Gotify sender and stop on tab leave',
    (tester) async {
      final h = _Harness();
      try {
        await h.mount(tester);
        h.clipboard.text = 'pasted';
        await tester.tap(find.byTooltip('Send clipboard content'));
        await tester.pumpAndSettle();
        expect(h.gotify.sent.single.payload['content'], 'pasted');
        await tester.tap(
          find.byKey(const ValueKey('clipboard-auto-send-toggle')),
        );
        await tester.pump();
        h.clipboard.text = 'automatic';
        await tester.pump(const Duration(milliseconds: 500));
        expect(h.gotify.sent.last.payload['content'], 'automatic');
        h.container.read(_active.notifier).state = false;
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('clipboard-auto-send-toggle')),
              )
              .isSelected,
          isFalse,
        );
        h.clipboard.text = 'not sent';
        await tester.pump(const Duration(seconds: 1));
        expect(h.gotify.sent, hasLength(2));
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'failure keeps composer and retry reuses message ID; disconnect disables send',
    (tester) async {
      final h = _Harness();
      try {
        await h.mount(tester);
        h.gotify.fail = true;
        await tester.enterText(
          find.byKey(const ValueKey('gotify-text-input')),
          'retry',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('gotify-text-send')));
        await tester.pumpAndSettle();
        final id = h.gotify.sent.single.eventId;
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('gotify-text-input')),
              )
              .controller!
              .text,
          'retry',
        );
        h.gotify.fail = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(h.gotify.sent.last.eventId, id);
        h.gotify.disconnect();
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('gotify-text-send')),
              )
              .onPressed,
          isNull,
        );
        expect(
          await h.container
              .read(textSendControllerProvider)
              .send('shared while offline'),
          isFalse,
        );
        expect(
          h.container.read(gotifyTextSessionProvider).messages.last.content,
          'shared while offline',
        );
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'Gotify settings registration toggle removes virtual server and falls back atomically',
    (tester) async {
      final h = _Harness(settings: true);
      try {
        await h.mount(tester, settings: true);
        expect(
          find.byKey(const ValueKey('server-tile-$gotifyTextServerId')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Register as a text server'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final entry = find.ancestor(
          of: find.text('Register as a text server'),
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_BooleanEntry',
          ),
        );
        final toggle = find.descendant(
          of: entry,
          matching: find.byType(Switch),
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          h.config.state.requireValue.gotify.registerAsTextServer,
          isFalse,
        );
        expect(
          h.config.state.requireValue.activeTextServerId,
          h.config.state.requireValue.servers.single.id,
        );
        expect(
          find.byKey(const ValueKey('server-tile-$gotifyTextServerId')),
          findsNothing,
        );
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets('real-time text controls fit a narrow phone screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    final h = _Harness();
    try {
      await h.mount(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await h.dispose(tester);
      await tester.binding.setSurfaceSize(null);
    }
  });
}
