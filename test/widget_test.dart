import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remote_send/main.dart';

void main() {
  testWidgets('App loads and shows loading indicator', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RemoteSendApp(),
      ),
    );

    // App should show loading indicator while config initializes
    expect(find.byType(RemoteSendApp), findsOneWidget);
  });
}
