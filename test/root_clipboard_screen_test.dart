import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/l10n/app_localizations.dart';
import 'package:remote_send/models/root_clipboard.dart';
import 'package:remote_send/providers/root_clipboard_provider.dart';
import 'package:remote_send/screens/root_clipboard_screen.dart';
import 'package:remote_send/services/root_clipboard_service.dart';

class _Bridge extends RootClipboardService {
  final stream = StreamController<RootClipboardEvent>.broadcast(sync: true);
  int starts = 0;
  int stops = 0;
  int reads = 0;
  int session = 0;
  final writes = <String>[];
  bool deny = false;
  bool mismatch = false;
  Completer<RootClipboardInfo>? pendingStart;
  Completer<RootClipboardSnapshot>? pendingRead;
  static const secret = 'PRIVATE CLIPBOARD BODY';
  RootClipboardSnapshot snapshot(String text, {bool internal = false}) =>
      RootClipboardSnapshot(
        RootClipboardMetadata(
          kind: RootClipboardKind.text,
          bytes: utf8.encode(text).length,
          internal: internal,
        ),
        text,
      );
  @override
  Stream<RootClipboardEvent> get events => stream.stream;
  @override
  Future<RootClipboardInfo> start() async {
    starts++;
    if (deny) {
      throw PlatformException(code: 'root_unavailable', message: secret);
    }
    if (pendingStart != null) return pendingStart!.future;
    return RootClipboardInfo(
      session: ++session,
      sdk: 35,
      uid: 2000,
      userId: 0,
      api: 'ATTRIBUTION_USER_DEVICE',
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<RootClipboardSnapshot> read() async {
    reads++;
    return pendingRead?.future ?? snapshot(secret);
  }

  @override
  Future<RootClipboardSnapshot> writeText(String text) async {
    writes.add(text);
    return snapshot(mismatch ? 'changed' : text, internal: true);
  }
}

class _Harness {
  _Harness({bool supported = true}) {
    container = ProviderContainer(
      overrides: [
        rootClipboardSupportedProvider.overrideWithValue(supported),
        rootClipboardServiceProvider.overrideWithValue(bridge),
      ],
    );
  }
  final bridge = _Bridge();
  late final ProviderContainer container;
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(tester.element(find.byType(Scaffold))).push<void>(
        MaterialPageRoute<void>(builder: (_) => const RootClipboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String action) async {
    final finder = find.byKey(ValueKey('root-clipboard-$action'));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await bridge.stream.close();
  }
}

void main() {
  testWidgets(
    'opening never requests root; starting and reading show metadata but not bodies; leaving stops',
    (tester) async {
      final h = _Harness();
      try {
        await h.mount(tester);
        expect(h.bridge.starts, 0);
        expect(h.bridge.reads, 0);
        await h.tap(tester, 'start');
        await tester.pumpAndSettle();
        expect(h.bridge.starts, 1);
        expect(
          h.container.read(rootClipboardDiagnosticsProvider).connected,
          isTrue,
        );
        h.bridge.stream.add(
          RootClipboardEvent(
            session: 1,
            metadata: const RootClipboardMetadata(
              kind: RootClipboardKind.sensitive,
            ),
          ),
        );
        await tester.pump();
        expect(h.container.read(rootClipboardDiagnosticsProvider).changes, 1);
        await h.tap(tester, 'read');
        await tester.pumpAndSettle();
        expect(h.bridge.reads, 1);
        expect(find.textContaining(_Bridge.secret), findsNothing);
        expect(
          h.container.read(rootClipboardDiagnosticsProvider).last!.bytes,
          utf8.encode(_Bridge.secret).length,
        );
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        expect(h.bridge.stops, greaterThanOrEqualTo(1));
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets(
    'test writes require confirmation and preserve the exact probe; mismatch is reported',
    (tester) async {
      final h = _Harness();
      try {
        await h.mount(tester);
        await h.tap(tester, 'start');
        await tester.pumpAndSettle();
        await h.tap(tester, 'probe');
        await tester.pumpAndSettle();
        expect(h.bridge.writes, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(h.bridge.writes, isEmpty);
        await h.tap(tester, 'probe');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(h.bridge.writes.single, RootClipboardService.probeText);
        expect(
          h.container.read(rootClipboardDiagnosticsProvider).probeMatched,
          isTrue,
        );
        expect(find.text(RootClipboardService.probeText), findsNothing);
        h.bridge.mismatch = true;
        await h.tap(tester, 'probe');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(
          h.container.read(rootClipboardDiagnosticsProvider).probeMatched,
          isFalse,
        );
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets('authorization failure is sanitized and can be retried', (
    tester,
  ) async {
    final h = _Harness();
    h.bridge.deny = true;
    try {
      await h.mount(tester);
      await h.tap(tester, 'start');
      await tester.pumpAndSettle();
      expect(
        h.container.read(rootClipboardDiagnosticsProvider).errorCode,
        'root_unavailable',
      );
      expect(find.textContaining(_Bridge.secret), findsNothing);
      expect(h.bridge.stops, greaterThanOrEqualTo(1));
      h.bridge.deny = false;
      await h.tap(tester, 'start');
      await tester.pumpAndSettle();
      expect(
        h.container.read(rootClipboardDiagnosticsProvider).connected,
        isTrue,
      );
      expect(
        h.container.read(rootClipboardDiagnosticsProvider).errorCode,
        isNull,
      );
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets('stop invalidates pending read and stale session notifications', (
    tester,
  ) async {
    final h = _Harness();
    try {
      await h.mount(tester);
      await h.tap(tester, 'start');
      await tester.pumpAndSettle();
      h.bridge.pendingRead = Completer();
      await h.tap(tester, 'read');
      await h.tap(tester, 'stop');
      await tester.pumpAndSettle();
      h.bridge.pendingRead!.complete(h.bridge.snapshot('stale'));
      await tester.pumpAndSettle();
      expect(h.container.read(rootClipboardDiagnosticsProvider).last, isNull);
      await h.tap(tester, 'start');
      await tester.pumpAndSettle();
      h.bridge.stream.add(
        const RootClipboardEvent(
          session: 1,
          stopped: true,
          errorCode: 'disconnected',
        ),
      );
      h.bridge.stream.add(
        const RootClipboardEvent(
          session: 1,
          metadata: RootClipboardMetadata(
            kind: RootClipboardKind.text,
            bytes: 5,
          ),
        ),
      );
      await tester.pump();
      final state = h.container.read(rootClipboardDiagnosticsProvider);
      expect(state.info!.session, 2);
      expect(state.changes, 0);
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets('stopping pending authorization ignores a late ready reply', (
    tester,
  ) async {
    final h = _Harness();
    h.bridge.pendingStart = Completer();
    try {
      await h.mount(tester);
      await h.tap(tester, 'start');
      await h.tap(tester, 'stop');
      await tester.pumpAndSettle();
      h.bridge.pendingStart!.complete(
        const RootClipboardInfo(
          session: 1,
          sdk: 35,
          uid: 2000,
          userId: 0,
          api: 'USER',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        h.container.read(rootClipboardDiagnosticsProvider).connected,
        isFalse,
      );
      expect(h.bridge.stops, greaterThanOrEqualTo(1));
    } finally {
      await h.dispose(tester);
    }
  });

  testWidgets(
    'unsupported desktop does not instantiate or authorize the bridge',
    (tester) async {
      final h = _Harness(supported: false);
      try {
        await h.mount(tester);
        expect(
          find.byKey(const ValueKey('root-clipboard-start')),
          findsNothing,
        );
        expect(h.bridge.starts, 0);
        expect(h.bridge.stream.hasListener, isFalse);
      } finally {
        await h.dispose(tester);
      }
    },
  );

  testWidgets('diagnostics fit narrow phones', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 850));
    final h = _Harness();
    try {
      await h.mount(tester);
      await h.tap(tester, 'start');
      await tester.pumpAndSettle();
      await h.tap(tester, 'read');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await h.dispose(tester);
      await tester.binding.setSurfaceSize(null);
    }
  });
}
