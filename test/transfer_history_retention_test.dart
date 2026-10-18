import 'package:flutter_test/flutter_test.dart';
import 'package:remote_send/services/transfer_history_retention.dart';

void main() {
  testWidgets(
    'disabled history keeps new records and re-enable restarts retention',
    (tester) async {
      final removed = <String>{};
      final history = TransferHistoryRetention(
        canPrune: () => true,
        onExpired: removed.addAll,
      );
      try {
        history.setEnabled(false);
        history.update(['first']);
        await tester.pump(const Duration(minutes: 10));
        expect(removed, isEmpty);
        history.setEnabled(true);
        await tester.pump(const Duration(minutes: 4));
        expect(removed, isEmpty);
        await tester.pump(const Duration(minutes: 1));
        expect(removed, {'first'});
      } finally {
        history.dispose();
      }
    },
  );

  testWidgets('disabling cancels an already-scheduled cleanup microtask', (
    tester,
  ) async {
    var busy = true;
    final removed = <String>{};
    final history = TransferHistoryRetention(
      canPrune: () => !busy,
      onExpired: removed.addAll,
    );
    try {
      history.update(['first']);
      await tester.pump(const Duration(minutes: 5));
      busy = false;
      history.update(['first']);
      history.setEnabled(false);
      await tester.pump();
      expect(removed, isEmpty);
    } finally {
      history.dispose();
    }
  });

  testWidgets('records expire exactly five minutes after completion', (
    tester,
  ) async {
    final removed = <String>{};
    final history = TransferHistoryRetention(
      canPrune: () => true,
      onExpired: removed.addAll,
    );
    try {
      history.update(['first']);
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(removed, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(removed, {'first'});
    } finally {
      history.dispose();
    }
  });

  testWidgets('later state updates do not restart an existing record timer', (
    tester,
  ) async {
    final removed = <String>{};
    final history = TransferHistoryRetention(
      canPrune: () => true,
      onExpired: removed.addAll,
    );
    try {
      history.update(['first']);
      await tester.pump(const Duration(minutes: 1));
      history.update(['first', 'second']);
      await tester.pump(const Duration(minutes: 4));
      expect(removed, {'first'});
      history.update(['second']);
      await tester.pump(const Duration(minutes: 1));
      expect(removed, {'first', 'second'});
    } finally {
      history.dispose();
    }
  });

  testWidgets(
    'expired records wait for idle and are then pruned asynchronously',
    (tester) async {
      var busy = true;
      final removed = <String>{};
      final history = TransferHistoryRetention(
        canPrune: () => !busy,
        onExpired: removed.addAll,
      );
      try {
        history.update(['first']);
        await tester.pump(const Duration(minutes: 6));
        expect(removed, isEmpty);
        busy = false;
        history.update(['first']);
        expect(removed, isEmpty); // No reentrant state writes from observers.
        await tester.pump();
        expect(removed, {'first'});
      } finally {
        history.dispose();
      }
    },
  );

  testWidgets('manual removal cancels the timer and a reused id starts fresh', (
    tester,
  ) async {
    final removed = <String>{};
    final history = TransferHistoryRetention(
      canPrune: () => true,
      onExpired: removed.addAll,
    );
    try {
      history.update(['first']);
      await tester.pump(const Duration(minutes: 4));
      history.update([]);
      history.update(['first']);
      await tester.pump(const Duration(minutes: 1));
      expect(removed, isEmpty);
      await tester.pump(const Duration(minutes: 4));
      expect(removed, {'first'});
    } finally {
      history.dispose();
    }
  });

  testWidgets('dispose cancels timers and pending cleanup microtasks', (
    tester,
  ) async {
    var busy = true;
    final removed = <String>{};
    final history = TransferHistoryRetention(
      canPrune: () => !busy,
      onExpired: removed.addAll,
    );
    history.update(['first']);
    await tester.pump(const Duration(minutes: 5));
    busy = false;
    history.update(['first']);
    history.dispose();
    await tester.pump(const Duration(minutes: 5));
    expect(removed, isEmpty);
  });
}
