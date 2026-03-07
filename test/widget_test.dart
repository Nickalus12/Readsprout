import 'package:flutter_test/flutter_test.dart';
import 'package:reading_sprout/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ReadingSproutApp());
    // App should show splash screen initially
    expect(find.text('Loading...'), findsOneWidget);
  });
}
