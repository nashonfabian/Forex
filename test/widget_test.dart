import 'package:flutter_test/flutter_test.dart';

import 'package:my_market_lab/app.dart';

void main() {
  testWidgets('startup error displays the database failure details', (WidgetTester tester) async {
    await tester.pumpWidget(const StartupErrorApp(message: 'test database error'));

    expect(find.text('The local database could not be opened.'), findsOneWidget);
    expect(find.text('test database error'), findsOneWidget);
  });
}
