import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xassistant/app/app.dart';

void main() {
  testWidgets('App loads and shows dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: XAssistantApp(),
      ),
    );

    // Verify app loads
    expect(find.byType(XAssistantApp), findsOneWidget);
  });
}
