import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/services/clipboard_sync_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows receipt passes the complete text and app locale to native',
    () async {
      const channel = ClipboardSyncPlatform.methods;
      MethodCall? received;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final clipboard = PlatformSyncClipboard(
        android: false,
        locale: () => 'zh',
      );
      await clipboard.notifyReceived('手机', '正文\n第二行');
      expect(received?.method, 'notifyClipboardReceived');
      expect(received?.arguments, {
        'deviceName': '手机',
        'text': '正文\n第二行',
        'locale': 'zh',
      });
    },
  );
}
