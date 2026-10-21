import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/services/clipboard_sync_history.dart';

void main() {
  test(
    'recent records remain local and records older than 30 days are archived by month',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'clipboard-history-test',
      );
      addTearDown(() => root.delete(recursive: true));
      final history = ClipboardSyncHistory(directoryProvider: () async => root);
      final now = DateTime.now();
      await history.record(
        eventId: 'recent',
        at: now,
        direction: 'sent',
        deviceName: 'PC',
        text: 'local recent',
      );
      final old = now.subtract(const Duration(days: 35));
      await history.record(
        eventId: 'old',
        at: old,
        direction: 'received',
        deviceName: 'Phone',
        text: 'local archive',
      );

      expect((await history.recent()).map((item) => item.id), ['recent']);
      final archives = await history.archives();
      final month =
          '${old.year.toString().padLeft(4, '0')}-${old.month.toString().padLeft(2, '0')}';
      expect(archives.keys, contains(month));
      expect(archives[month]!.single.text, 'local archive');
      final files = await root.list().cast<File>().toList();
      expect(files.every((file) => file.path.startsWith(root.path)), isTrue);

      await history.clear();
      expect(await history.recent(), isEmpty);
      expect(await history.archives(), isEmpty);
    },
  );
}
