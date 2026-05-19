import 'package:flutter_test/flutter_test.dart';

import 'package:money_manager/main.dart';

void main() {
  testWidgets('renders money manager shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MoneyManagerApp());

    expect(find.text('Money Manager'), findsOneWidget);
  });
}
