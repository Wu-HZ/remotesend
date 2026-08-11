import 'dart:async';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog with a countdown before the action button
/// becomes enabled. Returns true if the user confirmed, false otherwise.
Future<bool> showCountdownConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  int countdownSeconds = 10,
}) async {
  final completer = Completer<bool>();
  final countdownNotifier = ValueNotifier<int>(countdownSeconds);
  Timer? timer;

  timer = Timer.periodic(const Duration(seconds: 1), (t) {
    countdownNotifier.value--;
    if (countdownNotifier.value <= 0) {
      t.cancel();
    }
  });

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ValueListenableBuilder<int>(
      valueListenable: countdownNotifier,
      builder: (context, remaining, _) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                timer?.cancel();
                countdownNotifier.dispose();
                Navigator.pop(ctx);
                completer.complete(false);
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: remaining > 0
                  ? null
                  : () {
                      timer?.cancel();
                      countdownNotifier.dispose();
                      Navigator.pop(ctx);
                      completer.complete(true);
                    },
              child: Text(
                remaining > 0 ? '$confirmLabel ($remaining 秒)' : confirmLabel,
              ),
            ),
          ],
        );
      },
    ),
  );

  return completer.future;
}
